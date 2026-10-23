from io import StringIO
from rich.console import Console
from tools.chat_viewer.timings import parse_timings, detect_cache_misses
from tools.chat_viewer.timings_summary import build_timings_summary


def test_vllm_summary_uses_new_input_and_reasoning_split_and_sums_durations():
    first = parse_timings({'usage': {'prompt_tokens':1000, 'completion_tokens':100,
        'prompt_tokens_details':{'cached_tokens':800}, 'completion_tokens_details':{'reasoning_tokens':60}},
        'metrics':{'time_to_first_token_ms':200, 'generation_time_ms':990,
                   'speculative_decoding':{'num_draft_tokens':120,'num_accepted_draft_tokens':60,'mean_acceptance_length':3}}})
    second = parse_timings({'usage': {'prompt_tokens':1300, 'completion_tokens':200,
        'prompt_tokens_details':{'cached_tokens':1100}, 'completion_tokens_details':{'reasoning_tokens':40}},
        'metrics':{'time_to_first_token_ms':100, 'generation_time_ms':1990}})
    table = build_timings_summary([(1, first), (3, second)], 'vllm')
    assert [c.header.replace('\n', ' ') for c in table.columns] == ['cached tokens','in tokens','reasoning tokens','final tokens',
        'thinking %','total out tokens','draft','mean accept len','in duration','out duration','#']
    cells = [list(column._cells) for column in table.columns]
    assert cells[1] == ['200 @ ≈1,000.0 tok/s', '200 @ ≈2,000.0 tok/s', '400']
    assert cells[5][-1] == '300'
    assert cells[2][-1] == '100'
    assert cells[3][-1] == '200'
    assert cells[4][-1] == '33.3%'
    assert cells[6][0] == '60/120 50.0%'
    assert cells[8][-1] == '0.30 s'
    assert cells[9][-1] == '2.98 s'
    assert cells[-1] == ['#1', '#3', 'total']
    assert cells[0][-1] == ''
    assert 'ok' in cells[0][1]  # 1,000 input + 100 output, not 800 + 1,000 + 100
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
    table = build_timings_summary([(1, llama[0])], 'llama-server')
    assert 'reasoning tokens' not in [c.header.replace('\n', ' ') for c in table.columns]


def test_unknown_cache_or_reasoning_does_not_fabricate_new_or_final_counts():
    stats = parse_timings({'usage':{'prompt_tokens':100,'completion_tokens':20}})
    table = build_timings_summary([(1,stats)], 'vllm')
    cells = [list(c._cells) for c in table.columns]
    assert cells[1] == ['—','—']
    assert cells[2][-1] == cells[3][-1] == '—'
