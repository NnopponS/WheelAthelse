import csv

import pytest

from tools.pc_gui.csv_import import (
    ImportDateRequired,
    copy_imported_csv_for_export,
    delete_imported_csv,
    import_wheelathlete_csv,
    list_imported_csvs,
    read_wheelathlete_csv,
)


HEADER = [
    "session_id", "wheel", "seq", "timestamp_device_us",
    "timestamp_pc_monotonic_ns", "ax_raw", "ay_raw", "az_raw",
    "gx_raw", "gy_raw", "gz_raw",
]


def _write_csv(path, *, started_utc_ms=None):
    header = HEADER + (["started_utc_ms"] if started_utc_ms is not None else [])
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        for index, side in enumerate(("L", "R")):
            row = ["old-session-id", side, index, index * 10_000,
                   1_000_000_000 + index * 10_000_000, 1, 2, 3, 4, 5, 6]
            if started_utc_ms is not None:
                row.append(started_utc_ms)
            writer.writerow(row)


def test_import_uses_recorded_date_and_keeps_an_unchanged_managed_copy(tmp_path):
    source = tmp_path / "source.csv"
    _write_csv(source, started_utc_ms=1_750_000_000_000)
    original = source.read_bytes()

    imported = import_wheelathlete_csv(source, tmp_path / "WheelAthlete")

    assert imported["started_utc_ms"] == 1_750_000_000_000
    assert imported["sample_counts"] == {"L": 1, "R": 1, "C": 0}
    assert imported["is_imported_csv"] is True
    assert (tmp_path / "WheelAthlete" / imported["imported_file"]).read_bytes() == original
    assert source.read_bytes() == original
    assert list_imported_csvs(tmp_path / "WheelAthlete") == [imported]


def test_import_without_date_requires_a_user_supplied_date(tmp_path):
    source = tmp_path / "undated.csv"
    _write_csv(source)

    with pytest.raises(ImportDateRequired):
        import_wheelathlete_csv(source, tmp_path / "WheelAthlete")

    imported = import_wheelathlete_csv(
        source, tmp_path / "WheelAthlete", date_if_missing_ms=1_750_000_000_000
    )
    assert imported["started_utc_ms"] == 1_750_000_000_000


def test_import_and_reexport_collision_never_overwrites_existing_csv(tmp_path):
    library = tmp_path / "WheelAthlete"
    first_source = tmp_path / "same.csv"
    second_source = tmp_path / "second.csv"
    _write_csv(first_source)
    _write_csv(second_source)
    first = import_wheelathlete_csv(
        first_source, library, date_if_missing_ms=1_750_000_000_000
    )
    second = import_wheelathlete_csv(
        first_source, library, date_if_missing_ms=1_750_000_000_000
    )
    destination = tmp_path / "Exports"
    preserved = copy_imported_csv_for_export(first, destination)
    preserved.write_text("keep this file", encoding="utf-8")

    exported = copy_imported_csv_for_export(second, destination)

    assert exported != preserved
    assert preserved.read_text(encoding="utf-8") == "keep this file"
    assert exported.read_bytes() == first_source.read_bytes()


def test_import_rejects_non_wheelathlete_csv(tmp_path):
    source = tmp_path / "other.csv"
    source.write_text("date,temperature\n2026-01-01,20\n", encoding="utf-8")

    with pytest.raises(ValueError, match="WheelAthlete CSV"):
        read_wheelathlete_csv(source)


def test_failed_csv_copy_removes_only_its_partial_destination(tmp_path, monkeypatch):
    import tools.pc_gui.csv_import as csv_import

    source = tmp_path / "source.csv"
    _write_csv(source)
    library = tmp_path / "WheelAthlete"

    def fail_after_partial_write(_source, output, *, length):
        output.write(b"partial")
        raise OSError("simulated disk failure")

    monkeypatch.setattr(csv_import.shutil, "copyfileobj", fail_after_partial_write)

    with pytest.raises(OSError, match="simulated disk failure"):
        import_wheelathlete_csv(
            source, library, date_if_missing_ms=1_750_000_000_000
        )

    assert not (library / "source.csv").exists()


def test_csv_copy_publishes_only_after_the_temporary_copy_is_complete(tmp_path, monkeypatch):
    import tools.pc_gui.csv_import as csv_import
    from threading import Event, Thread

    source = tmp_path / "source.csv"
    source.write_bytes(b"complete source csv contents")
    destination = tmp_path / "Exports"
    started, resume, finished = Event(), Event(), Event()
    result, errors = [], []
    copy_fileobj = csv_import.shutil.copyfileobj

    def hold_after_partial_copy(input_file, output, *, length):
        content = input_file.read(length)
        output.write(content[:8])
        started.set()
        assert resume.wait(2)
        output.write(content[8:])
        copy_fileobj(input_file, output, length=length)

    def copy_in_background():
        try:
            result.append(csv_import._copy_create_only(source, destination, source.name))
        except Exception as exc:
            errors.append(exc)
        finally:
            finished.set()

    monkeypatch.setattr(csv_import.shutil, "copyfileobj", hold_after_partial_copy)
    worker = Thread(target=copy_in_background, daemon=True)
    worker.start()
    assert started.wait(1)
    assert not (destination / source.name).exists()
    resume.set()
    assert finished.wait(2)
    worker.join(1)

    assert not errors
    assert result[0].read_bytes() == source.read_bytes()
    assert not list(destination.glob(".wa-*.tmp"))


def test_delete_removes_only_the_managed_copy_and_sidecar(tmp_path):
    source = tmp_path / "source.csv"
    library = tmp_path / "WheelAthlete"
    _write_csv(source)
    imported = import_wheelathlete_csv(
        source, library, date_if_missing_ms=1_750_000_000_000
    )

    delete_imported_csv(imported, library)

    assert source.is_file()
    assert not (library / imported["imported_file"]).exists()
    assert not list_imported_csvs(library)
