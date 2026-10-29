"""Comparable backend summary tables; counts and durations stay explicit."""
from dataclasses import dataclass

import rich
from rich.table import Table
from .timings import ModelTimings, detect_cache_misses


@dataclass(frozen=True)
class TimingEntry:
    """A single assistant timing row, keyed by its message number in the trace."""

    message_number: int
    timings: ModelTimings


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

def italic(text: str) -> str:
    return f"[italic]{text}[/]"

def red(text: str) -> str:
    return f"[red]{text}[/]"

def green(text: str) -> str:
    return f"[green]{text}[/]"

def build_timings_summary(entries: list[TimingEntry], backend: str) -> Table:
    """Entries carry the assistant message's number in the trace, including unmeasured turns."""
    # TODO what happens if you are missing timings on an assistant message? right now IIAC we would skip sending it here and we wouldn't realize it...
    #   TODO should probably indicate missing in TimingEntry so we can factor that into cache hit/miss and at a minimum show missing timing info in table (b/c then you might miss overall durations or average tok/s b/c of missing timing)

    from rich import box
    table = Table(
        show_header=True,
        box = None,
        # box=box.SIMPLE, # results in line under header and extra blank above totals row b/c of add_section()
        padding=(0, 1),
        # row_styles=['', 'dim'],
    )
    table.caption = 'Durations are summed phase times, not elapsed agent wall time.'

    show_out_split_columns = backend != 'llama-server' # vllm/sglang give us reasoning vs final split within output tokens
    # llama-server doesn't expose mean accept len at all... and then models w/o draft would not have draft stats at all
    show_draft_column = any([e.timings.draft_tokens is not None for e in entries])
    show_mean_accept_len_column = any([e.timings.mean_acceptance_length is not None for e in entries])

    # * headers
    table.add_column('cached', justify='right')
    table.add_column('in', justify='right')
    table.add_column('out', justify='right')
    dim_not_bold = 'dim not bold'
    if show_out_split_columns:
        table.add_column('reasoning', justify='right', header_style=dim_not_bold)
        table.add_column('final', justify='right', header_style=dim_not_bold)
    if show_draft_column:
        table.add_column('draft', justify='right', header_style=dim_not_bold)
    if show_mean_accept_len_column:
        table.add_column('accept\nlen', justify='right', no_wrap=True, header_style=dim_not_bold)

    table.add_column('in', justify='right')
    table.add_column('out', justify='right')
    table.add_column('') # message number, no need for a header

    # * per message timing rows
    #
    # initialize:
    total_in = total_out = total_reasoning = total_final = 0
    total_drafted = total_accepted = 0
    show_total_for_in = show_total_for_reasoning = True
    in_durations, out_durations = [], []

    cache_states = detect_cache_misses([entry.timings for entry in entries])
    for entry, cache in zip(entries, cache_states):
        message_number = entry.message_number
        stats = entry.timings
        new_in_tokens = stats.uncached_prompt_tokens

        # cached tokens
        cell_cached = _count(stats.cached_tokens)
        if stats.formatted_cache_ratio is not None:
            cell_cached += dim(f'\n{stats.formatted_cache_ratio} hit')
        if cache:
            cell_cached += red(f'\nMISS {cache.formatted_missing_tokens}') if cache.is_cache_miss else green('\nok')

        # rates
        estimated_rates = backend == 'llama-server'
        input_rate = stats.prompt_tokens_per_second if estimated_rates else stats.estimated_input_tokens_per_second
        output_rate = stats.predicted_tokens_per_second if estimated_rates else stats.estimated_decode_tokens_per_second

        cell_in = _tokens_rate(new_in_tokens, input_rate, not estimated_rates)
        cell_out = _tokens_rate(stats.predicted_tokens, output_rate, not estimated_rates)
        message_row = [cell_cached, cell_in, cell_out]

        # conditionally show output breakdown (reasoning vs final)
        reasoning_count = stats.reasoning_tokens
        valid_reasoning = reasoning_count is not None
        reasoning_out_of_bounds = reasoning_count and (reasoning_count < 0 or stats.predicted_tokens < reasoning_count)  # or 0 handles None gracefully
        if reasoning_out_of_bounds:
            # PRN if this ever arises we can address it at the time
            # and for now I want to show the reasoning_count below even if "out of bounds" b/c there is a value returned so we need to show that
            rich.print(f"[red] UNEXPECTED, reasoning_count is outside of expected bounds: 0 <= {reasoning_count=} <= {stats.predicted_tokens=}[/]")
        if show_out_split_columns:
            if valid_reasoning:
                final_count = stats.predicted_tokens - reasoning_count  # just let it go negative, that's fine if there is an out of bounds
                think_percent = f'{reasoning_count / stats.predicted_tokens * 100:.1f}%' if stats.predicted_tokens else '—'
                message_row.append(dim(_count(reasoning_count) + " " + think_percent))
                message_row.append(dim(_count(final_count)))
            else:
                message_row.extend(['', ''])

            show_total_for_reasoning &= valid_reasoning

            if valid_reasoning:
                total_reasoning += reasoning_count
                total_final += final_count

        # draft tokens
        if show_draft_column:
            if stats.draft_tokens is not None:
                cell_draft = f'{_count(stats.draft_tokens_accepted)}/{_count(stats.draft_tokens)}'
                total_drafted += stats.draft_tokens or 0
                total_accepted += stats.draft_tokens_accepted or 0
                if stats.formatted_acceptance_rate:
                    cell_draft += f' {stats.formatted_acceptance_rate}'
                message_row.append(dim(cell_draft))
            else:
                message_row.append(dim('—'))
        if show_mean_accept_len_column:
            cell_mean_accept_len = '—' if stats.mean_acceptance_length is None else f'{stats.mean_acceptance_length:.2f}'
            message_row.append(dim(cell_mean_accept_len))

        input_ms = stats.prompt_ms if estimated_rates else stats.time_to_first_token_ms
        output_ms = stats.predicted_ms if estimated_rates else stats.generation_time_ms
        message_row += [
            _duration(input_ms),
            _duration(output_ms),
            f'#{message_number}',
        ]
        table.add_row(*message_row)

        # running totals
        show_total_for_in &= new_in_tokens is not None
        total_in += new_in_tokens or 0
        total_out += stats.predicted_tokens
        in_durations.append(input_ms)
        out_durations.append(output_ms)

    # * totals row
    total_for_cached = 'total'
    total_for_in = _count(total_in) if show_total_for_in else '—'
    total_row = [total_for_cached, total_for_in]

    total_for_out = _count(total_out)
    total_row.append(total_for_out)

    if show_out_split_columns:
        percent = f'{total_reasoning / total_out * 100:.1f}%' if show_total_for_reasoning and total_out else '—'
        count = _count(total_reasoning) if show_total_for_reasoning else '—'
        total_for_reasoning = count + " " + percent
        total_for_final = _count(total_final) if show_total_for_reasoning else '—'
        total_row.extend([dim(total_for_reasoning), dim(total_for_final)])

    if show_draft_column:
        if total_drafted:
            total_acceptance_rate = f"{(total_accepted/total_drafted*100):.1f}%"
        else:
            total_acceptance_rate = ''
        total_row.append(f'{_count(total_accepted)}/{_count(total_drafted)} {total_acceptance_rate}'.strip())
    if show_mean_accept_len_column:
        # TODO weighted average of the mean accept len?
        total_row.append('')

    def _total_duration(durations):
        # Do not show total duration when any individual duration is missing.
        if all(v is not None for v in durations):
            return _duration(sum(durations))
        return '—'

    total_for_in_duration = _total_duration(in_durations)
    total_for_out_duration = _total_duration(out_durations)
    total_row.extend([
        total_for_in_duration,
        total_for_out_duration,
        '', # message_number
    ])

    table.add_section()
    table.add_row(*total_row, style='bold')

    return table
