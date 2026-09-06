from pathlib import Path

from tools.pc_gui.experiments import ExperimentStore, ExperimentTemplate


def test_experiment_store_round_trip_and_delete(tmp_path: Path):
    store = ExperimentStore(tmp_path / "experiments.json")
    template = ExperimentTemplate.new(
        name="Sprint baseline",
        athlete="Athlete A",
        topic="Sprint",
        sample_rate_hz=200,
        notes="Indoor baseline",
        tags=("baseline", "indoor"),
    )
    saved = store.upsert(template)
    assert saved == [template]
    loaded = store.load()
    assert loaded == [template]
    assert loaded[0].tags == ("baseline", "indoor")

    assert store.delete(template.id) == []
    assert store.load() == []


def test_experiment_template_rejects_invalid_rate():
    try:
        ExperimentTemplate.new(name="bad", sample_rate_hz=120)
    except ValueError as exc:
        assert "50, 100, or 200" in str(exc)
    else:
        raise AssertionError("invalid rate was accepted")
