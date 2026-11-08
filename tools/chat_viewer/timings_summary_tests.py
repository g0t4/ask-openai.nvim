from io import StringIO
import re
from rich.console import Console
from tools.chat_viewer.timings import parse_timings, detect_cache_misses
from tools.chat_viewer.timings_summary import TimingEntry, build_timings_summary, _token_rate


def strip_markup(text):
    """Remove rich markup tags so cells can be compared as plain text."""
    return re.sub(r'\[/?[^\]]*\]', '', text)


def test_vllm_summary_uses_new_input_and_reasoning_split_and_sums_durations():
    first = parse_timings({'usage': {'prompt_tokens':1000, 'completion_tokens':100,
        'prompt_tokens_details':{'cached_tokens':800}, 'completion_tokens_details':{'reasoning_tokens':60}},
        'metrics':{'time_to_first_token_ms':200, 'generation_time_ms':990,
                   'speculative_decoding':{'num_draft_tokens':120,'num_accepted_draft_tokens':60,'mean_acceptance_length':3}}})
    second = parse_timings({'usage': {'prompt_tokens':1300, 'completion_tokens':200,
        'prompt_tokens_details':{'cached_tokens':1100}, 'completion_tokens_details':{'reasoning_tokens':40}},
        'metrics':{'time_to_first_token_ms':100, 'generation_time_ms':1990}})
    table = build_timings_summary([TimingEntry(1, first), TimingEntry(3, second)], 'vllm')
    assert [c.header.replace('\n', ' ') for c in table.columns] == ['cached','in','in tok/s','out','out tok/s',
        'reasoning','final','draft','draft %','accept len','in','out','']
    cells = [list(column._cells) for column in table.columns]
    assert [strip_markup(x) for x in cells[1]] == ['200 @', '200 @', '400 @']   # in count
    assert [strip_markup(x) for x in cells[2]] == ['≈1,000 tok/s', '≈2,000 tok/s', '≈1,333 tok/s']  # in rate
    assert [strip_markup(x) for x in cells[3]] == ['100 @', '200 @', '300 @']   # out count
    assert [strip_markup(x) for x in cells[4]] == ['≈100 tok/s', '≈100 tok/s', '≈101 tok/s']  # out rate
    assert strip_markup(cells[5][-1]) == '100 33%'  # reasoning
    assert strip_markup(cells[6][-1]) == '200'        # final
    assert strip_markup(cells[7][0]) == '60/120'       # draft count
    assert strip_markup(cells[8][0]) == '50%'          # draft acceptance rate
    assert strip_markup(cells[9][0]) == '3.00'         # accept len
    assert strip_markup(cells[10][-1]) == '0.30 s'     # in duration
    assert strip_markup(cells[11][-1]) == '2.98 s'     # out duration
    assert [strip_markup(x) for x in cells[-1]] == ['#1', '#3', '']
    assert strip_markup(cells[0][-1]) == '1,900'      # cached totals
    for width in [100, 180]:
        output = StringIO()
        Console(file=output, width=width).print(table)
        assert 'overall' not in output.getvalue()
        assert 'TTFT' not in output.getvalue()
        assert all(len(line) <= width for line in output.getvalue().splitlines())


def test_llama_and_vllm_cache_continuity_use_the_same_total_input_math():
    llama = [parse_timings({'timings':{'cache_n':80,'prompt_n':20,'predicted_n':10}}),
             parse_timings({'timings':{'cache_n':100,'prompt_n':20,'predicted_n':5}})]
    vllm = [parse_timings({'usage':{'prompt_tokens':100,'completion_tokens':10,'prompt_tokens_details':{'cached_tokens':80}}}),
            parse_timings({'usage':{'prompt_tokens':120,'completion_tokens':5,'prompt_tokens_details':{'cached_tokens':100}}})]
    assert detect_cache_misses(llama)[1] == detect_cache_misses(vllm)[1]
    assert detect_cache_misses(vllm)[1].missing_tokens == -10
    assert detect_cache_misses([llama[0], vllm[1]]) == [None, None]
    table = build_timings_summary([TimingEntry(1, llama[0])], 'llama-server')
    assert 'reasoning' not in [c.header.replace('\n', ' ') for c in table.columns]


def test_unknown_cache_or_reasoning_does_not_fabricate_new_or_final_counts():
    stats = parse_timings({'usage':{'prompt_tokens':100,'completion_tokens':20}})
    table = build_timings_summary([TimingEntry(1, stats)], 'vllm')
    cells = [list(c._cells) for c in table.columns]
    assert [strip_markup(x) for x in cells[1]] == ['—']   # no new-input count
    assert strip_markup(cells[5][-1]) == ''               # no fabricated reasoning
    assert strip_markup(cells[6][-1]) == ''               # no fabricated final

def test_zero_reasoning_leaves_reasoning_column_blank():
    stats = parse_timings({'usage':{'prompt_tokens':100,'completion_tokens':50,
        'completion_tokens_details':{'reasoning_tokens':0}}})
    table = build_timings_summary([TimingEntry(1, stats)], 'vllm')
    cells = [list(c._cells) for c in table.columns]
    assert strip_markup(cells[5][0]) == ''                # reasoning column blank
    assert strip_markup(cells[6][0]) == '50'              # all output is final

def test_tokens_rate_under10_includes_decimal():
    _, rate = _token_rate(1, 9.3)
    assert "9.3" in strip_markup(rate)

def test_tokens_rate_above10__rounds_and_shows_no_decimal():
    _, rate = _token_rate(1, 11.3)
    assert "11" in strip_markup(rate)
    assert "11.3" not in strip_markup(rate)

    # rounds up
    _, rate = _token_rate(1, 11.6)
    assert "12" in strip_markup(rate)

def test_tokens_rate_over_one_thousand__shows_comma_on_rate():
    _, rate = _token_rate(1, 1001)
    assert "1,001" in strip_markup(rate)
