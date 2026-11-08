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
    return '—' if value is None else f'{value / 1000:.2f}{dim("s")}'


def _token_rate(count, rate, estimated=False):
    """Split a count and its tok/s rate into two cells so numeric values align."""
    count_cell = _count(count)
    if count is None or rate is None or rate <= 0:
        return count_cell, ''
    approx = '≈' if estimated else ''
    units = dim(' tok/s')
    if rate < 10:
        rate_cell = f'{approx}{rate:,.1f}{units}'
    else:
        rate_cell = f'{approx}{rate:,.0f}{units}'
    return count_cell + dim(' @'), rate_cell

# * book anchor constants: a rough, human-sized reference for the tok/s rates
#   300-page book ≈ 250 words/page ≈ 75,000 words; English ~1.3 tokens/word.
BOOK_PAGES = 300
BOOK_WORDS_PER_PAGE = 250
TOKENS_PER_WORD = 1.3
BOOK_WORDS = BOOK_PAGES * BOOK_WORDS_PER_PAGE
BOOK_TOKENS = int(BOOK_WORDS * TOKENS_PER_WORD)


def _human_duration(seconds):
    """Render a duration in seconds as a compact human-friendly string."""
    if seconds >= 3600:
        return f'{seconds / 3600:.1f} h'
    if seconds >= 60:
        return f'{seconds / 60:.1f} min'
    return f'{seconds:.1f} s'


def _aggregate_rate(total_tokens, durations_ms):
    """Average tok/s across the measured turns, if every duration is present."""
    if not total_tokens or not durations_ms:
        return None
    if any(duration is None for duration in durations_ms):
        return None
    total_ms = sum(durations_ms)
    if total_ms <= 0:
        return None
    return total_tokens / (total_ms / 1000)


def _book_anchor_blurb(read_rate, write_rate):
    """Anchor the read/write tok/s speeds against a 300-page book."""
    lines = [
        f'📖 Book anchor: a {BOOK_PAGES}-page book ≈ {BOOK_WORDS:,} words ≈ {BOOK_TOKENS:,} tokens.',
    ]
    if read_rate is not None:
        read_time = _human_duration(BOOK_TOKENS / read_rate)
        lines.append(f'  • read it at {read_rate:,.1f} tok/s (input) → {read_time}')
    else:
        lines.append('  • read time: — (no input rate measured)')
    if write_rate is not None:
        write_time = _human_duration(BOOK_TOKENS / write_rate)
        lines.append(f'  • write it at {write_rate:,.1f} tok/s (decode) → {write_time}')
    else:
        lines.append('  • write time: — (no decode rate measured)')
    return '\n'.join(lines)


def dim(text: str) -> str:
    return f"[dim]{text}[/]"

def italic(text: str) -> str:
    return f"[italic]{text}[/]"

def red(text: str) -> str:
    return f"[red]{text}[/]"

def green(text: str) -> str:
    return f"[green]{text}[/]"

def build_timings_summary(entries: list[TimingEntry], backend: str, expanded: bool = False) -> Table:
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

    # * expanded (--all) reveals extra detail; everything else shows always
    #   vllm/sglang give us a reasoning vs final split; llama-server doesn't expose mean accept len,
    #   and models without a draft have no draft stats at all.
    show_out_split_columns = expanded and backend != 'llama-server'
    show_draft_column = expanded and any([e.timings.draft_tokens is not None for e in entries])
    show_mean_accept_len_column = expanded and any([e.timings.mean_acceptance_length is not None for e in entries])

    # * headers
    table.add_column('cached', justify='right')
    table.add_column('in', justify='right')
    table.add_column('in\ntok/s', justify='right')
    table.add_column('out', justify='right')
    table.add_column('out\ntok/s', justify='right')
    dim_not_bold = 'dim not bold'
    if show_out_split_columns:
        table.add_column('reasoning', justify='right', header_style=dim_not_bold)
        table.add_column('final', justify='right', header_style=dim_not_bold)
    if show_draft_column:
        table.add_column('draft', justify='right', header_style=dim_not_bold)
        table.add_column('draft\n%', justify='right', header_style=dim_not_bold)
    if show_mean_accept_len_column:
        table.add_column('accept\nlen', justify='right', no_wrap=True, header_style=dim_not_bold)

    table.add_column('in', justify='right')
    table.add_column('out', justify='right')
    table.add_column('', justify='right')  # message number, no need for a header

    # * per message timing rows
    #
    # initialize:
    total_cached = 0
    total_in = total_out = total_reasoning = total_final = 0
    total_drafted = total_accepted = 0
    show_total_for_in = show_total_for_reasoning = True
    in_durations, out_durations = [], []
    exact_rates = backend == 'llama-server'

    cache_states = detect_cache_misses([entry.timings for entry in entries])
    for entry, cache in zip(entries, cache_states):
        message_number = entry.message_number
        stats = entry.timings
        new_in_tokens = stats.uncached_prompt_tokens

        # cached tokens
        cell_cached = _count(stats.cached_tokens)
        # TODO look into caching with vllm and sglang... the expected/actual difference is almost never aligned so showing MISS every time is not that useful until I understand why and if I want to distill that into a MISS / delta
        #  TODO if I don't find a good use for HIT/MISS then get rid of it here
        if expanded and backend == "llama-server" and cache and cache.is_cache_miss:
            # for llama-server only mark MISSes so I can investigate or at least so I don't mostly see `ok`/green when that' useless to know if it basically happens all the time
            #  no news (no ok) == good news!
            cell_cached += red(f'\nMISS {cache.formatted_missing_tokens}')

        # rates
        input_rate = stats.prompt_tokens_per_second if exact_rates else stats.estimated_input_tokens_per_second
        output_rate = stats.predicted_tokens_per_second if exact_rates else stats.estimated_decode_tokens_per_second

        count_in, rate_in = _token_rate(new_in_tokens, input_rate, not exact_rates)
        count_out, rate_out = _token_rate(stats.predicted_tokens, output_rate, not exact_rates)
        message_row = [cell_cached, count_in, rate_in, count_out, rate_out]

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
                if reasoning_count:
                    think_percent = f'{reasoning_count / stats.predicted_tokens * 100:.0f}%' if stats.predicted_tokens else '—'
                    message_row.append(dim(_count(reasoning_count) + " " + think_percent))
                else:
                    message_row.append('')  # no reasoning tokens, leave the column blank
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
                cell_draft_count = f'{_count(stats.draft_tokens_accepted)}/{_count(stats.draft_tokens)}'
                total_drafted += stats.draft_tokens or 0
                total_accepted += stats.draft_tokens_accepted or 0
                cell_draft_rate = stats.formatted_acceptance_rate or ''
                message_row += [dim(cell_draft_count), dim(cell_draft_rate)]
            else:
                message_row += [dim('—'), '']
        if show_mean_accept_len_column:
            cell_mean_accept_len = '—' if stats.mean_acceptance_length is None else f'{stats.mean_acceptance_length:.2f}'
            message_row.append(dim(cell_mean_accept_len))

        input_ms = stats.prompt_ms if exact_rates else stats.time_to_first_token_ms
        output_ms = stats.predicted_ms if exact_rates else stats.generation_time_ms
        message_row += [
            _duration(input_ms),
            _duration(output_ms),
            dim('#') + str(message_number),
        ]
        table.add_row(*message_row)

        # running totals
        show_total_for_in &= new_in_tokens is not None
        total_in += new_in_tokens or 0
        total_cached += stats.cached_tokens or 0
        total_out += stats.predicted_tokens
        in_durations.append(input_ms)
        out_durations.append(output_ms)

    # * totals row
    more_than_one = len(entries) > 1
    if more_than_one:

        # overall speeds = token-weighted (== time-weighted) average across the measured turns
        read_rate = _aggregate_rate(total_in, in_durations)
        write_rate = _aggregate_rate(total_out, out_durations)

        total_for_cached = _count(total_cached)
        if show_total_for_in:
            total_count_in, total_rate_in = _token_rate(total_in, read_rate, estimated=not exact_rates)
        else:
            total_count_in, total_rate_in = '—', ''
        total_row = [total_for_cached, total_count_in, total_rate_in]

        total_count_out, total_rate_out = _token_rate(total_out, write_rate, estimated=not exact_rates)
        total_row.extend([total_count_out, total_rate_out])

        if show_out_split_columns:
            if show_total_for_reasoning:
                total_for_final = _count(total_final)
                if total_reasoning:
                    percent = f'{total_reasoning / total_out * 100:.0f}%' if total_out else '—'
                    total_for_reasoning = _count(total_reasoning) + " " + percent
                else:
                    total_for_reasoning = ''  # no reasoning tokens, leave the column blank
            else:
                total_for_reasoning = '—'
                total_for_final = '—'
            total_row.extend([dim(total_for_reasoning), dim(total_for_final)])

        if show_draft_column:
            if total_drafted:
                total_acceptance_rate = f"{(total_accepted/total_drafted*100):.0f}%"
            else:
                total_acceptance_rate = ''
            total_row += [
                dim(f'{_count(total_accepted)}/{_count(total_drafted)}'),
                dim(total_acceptance_rate),
            ]
        if show_mean_accept_len_column:
            # TODO weighted average of the mean accept len?
            total_row.append('')

        def _total_duration(durations):
            # Do not show total duration when any individual duration is missing.
            if all(v is not None for v in durations):
                return _duration(sum(durations))
            return '—'

        total_row.extend([
            _total_duration(in_durations),
            _total_duration(out_durations),
            '',  # message_number
        ])

        table.add_section()
        table.add_row(*total_row, style='bold')


    # # * book anchor blurb (appended to the caption, which renders at the end of the table)
    # table.caption = (
    #     'Durations are summed phase times, not elapsed agent wall time.\n'
    #     # + _book_anchor_blurb(read_rate, write_rate)
    # )

    return table
