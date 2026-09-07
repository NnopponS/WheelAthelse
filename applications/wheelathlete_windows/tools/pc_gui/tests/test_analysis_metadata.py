import pytest

from tools.pc_gui.analysis_contract import build_analysis, validate_analysis


def example():
    times = [index * 0.05 for index in range(20)]
    return build_analysis(
        times=times,
        xy=[[time, 0.0] for time in times],
        flags=[[] for _ in times],
        metadata={"nested": {"values": [1, True, None, "fixture"]}},
    )


def test_json_metadata_supported_by_both_clients():
    validate_analysis(example())


def test_boolean_schema_is_not_version_one():
    value = example()
    value["schema_version"] = True
    with pytest.raises(ValueError, match="schema"):
        validate_analysis(value)


@pytest.mark.parametrize(
    "bad", [{1: "numeric key"}, {"nested": {2: 3}}, {"tuple": (1, 2)}]
)
def test_python_cannot_publish_metadata_rejected_by_dart(bad):
    value = example()
    value["metadata"] = bad
    with pytest.raises(ValueError, match="Metadata"):
        validate_analysis(value)


def test_cyclic_metadata_fails_without_unbounded_recursion():
    value = example()
    value["metadata"]["cycle"] = value["metadata"]
    with pytest.raises(ValueError):
        validate_analysis(value)
