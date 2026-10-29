"""Comparable backend summary tables; counts and durations stay explicit."""
from rich.table import Table
from .timings import ModelTimings, detect_cache_misses


def _count(value):
    return '—' if value is None else f'{value:,}'


def _duration(value):
    return '—' if value is None else f'{value / 1000:.2f} s'


def _tokens_rate(count, rate, estimated=False):
    text = _count(count)
    if count is not None and rate is not None and rate > 0:
        text += f' @ {"≈" if estimated else ""}{rate:,.1f} tok/s'
    return text

def dim(text: str) -> str:
    return f"[dim]{text}[/]"

def red(text: str) -> str:
    return f"[red]{text}[/]"

def green(text: str) -> str:
    return f"[green]{text}[/]"

def build_timings_summary(entries: list[tuple[int, ModelTimings]], backend: str) -> Table:
    """Entries carry assistant-only ordinal numbers, including unmeasured turns."""

    table = Table(show_header=True, box=None, padding=(0, 1), row_styles=['', 'dim'])
    table.caption = 'Durations are summed phase times, not elapsed agent wall time.'

    # * headers
    headers = ['cached', 'in']

    split_output = backend != 'llama-server'
    if split_output:
        headers += ['reasoning', 'final', 'thinking %']

    headers += ['out' if split_output else 'out', 'draft', 'mean accept len', 'in', 'out', '#']

    for header in headers:
        table.add_column(header, justify='right', no_wrap=True)

    # * per message timing rows
    #
    # initialize:
    total_in = total_out = total_reasoning = total_final = 0
    known_in = known_reasoning = True
    in_durations, out_durations = [], []

    cache_states = detect_cache_misses([stats for _, stats in entries])
    for (ordinal, stats), cache in zip(entries, cache_states):
        new_tokens = stats.uncached_prompt_tokens
        native = backend == 'llama-server'
        input_rate = stats.prompt_tokens_per_second if native else stats.estimated_input_tokens_per_second
        output_rate = stats.predicted_tokens_per_second if native else stats.estimated_decode_tokens_per_second
        input_ms = stats.prompt_ms if native else stats.time_to_first_token_ms
        output_ms = stats.predicted_ms if native else stats.generation_time_ms
        cached = _count(stats.cached_tokens)
        if stats.formatted_cache_ratio is not None:
            cached += dim(f'\n{stats.formatted_cache_ratio} hit')
        if cache:
            cached += red(f'\nMISS {cache.formatted_missing_tokens}') if cache.is_cache_miss else green('\nok')
        row = [cached, _tokens_rate(new_tokens, input_rate, not native)]
        reasoning = stats.reasoning_tokens
        valid_reasoning = reasoning is not None and 0 <= reasoning <= stats.predicted_tokens
        if split_output:
            final = stats.predicted_tokens - reasoning if valid_reasoning else None
            think_percent = f'{reasoning / stats.predicted_tokens * 100:.1f}%' if valid_reasoning and stats.predicted_tokens else '—'
            cell_reasoning = dim(_count(reasoning if valid_reasoning else None))
            cell_thinking_percent = dim(think_percent)
            row += [cell_reasoning, _count(final), cell_thinking_percent]
            known_reasoning &= valid_reasoning
            if valid_reasoning:
                total_reasoning += reasoning
                total_final += final
        draft = '—'
        if stats.draft_tokens is not None:
            draft = f'{_count(stats.draft_tokens_accepted)}/{_count(stats.draft_tokens)}'
            if stats.formatted_acceptance_rate:
                draft += f' {stats.formatted_acceptance_rate}'
        row += [_tokens_rate(stats.predicted_tokens, output_rate, not native), draft,
                '—' if stats.mean_acceptance_length is None else f'{stats.mean_acceptance_length:.2f}',
                _duration(input_ms), _duration(output_ms), f'#{ordinal}']
        table.add_row(*row)
        known_in &= new_tokens is not None
        total_in += new_tokens or 0
        total_out += stats.predicted_tokens
        in_durations.append(input_ms)
        out_durations.append(output_ms)

    # * totals row
    total = ['', _count(total_in) if known_in else '—']
    if split_output:
        total_for_percent = f'{total_reasoning / total_out * 100:.1f}%' if known_reasoning and total_out else '—'
        total_for_reasoning = _count(total_reasoning) if known_reasoning else '—'
        total_for_final = _count(total_final) if known_reasoning else '—'
        total += [total_for_reasoning, total_for_final, total_for_percent]
    # Deliberately avoid averaging per-request rates or summing cumulative cache counts.
    total += [_count(total_out), '', '',
              _duration(sum(in_durations)) if all(v is not None for v in in_durations) else '—',
              _duration(sum(out_durations)) if all(v is not None for v in out_durations) else '—', 'total']
    table.add_section()
    table.add_row(*total, style='bold')

    return table
