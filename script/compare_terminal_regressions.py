from pathlib import Path
import json,re
def failures(path):
    return set(re.findall(r"(?:Failure|Error):\n([^\n]+)",Path(path).read_text()))
baseline=failures('tmp/terminal-baseline-suite.log')
candidate=failures('tmp/terminal-feature-suite.log')
result={'baseline_sha':'9bc1d17614e667b1226671e413d4e5591d9b3380','baseline_summary':'468 tests / 5247 assertions; 34 failures, 26 errors',
        'candidate_summary':'482 tests / 5394 assertions; 33 failures, 25 errors',
        'new_failures':sorted(candidate-baseline),'remaining_baseline_failures':sorted(candidate&baseline),'repaired_relevant_fixture_cases':sorted(baseline-candidate)}
Path('docs/STARTRADER_TERMINAL_FILTER_REGRESSIONS.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'new_failures':result['new_failures'],'remaining_baseline_cases':len(candidate&baseline),'repaired_cases':result['repaired_relevant_fixture_cases']},indent=2))
assert not result['new_failures'], 'Candidate introduced a new failing identity'
