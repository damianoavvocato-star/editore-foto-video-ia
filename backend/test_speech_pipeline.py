"""Tests for the provider-neutral speech and subtitle pipeline."""
import pytest

from backend.speech_pipeline import (
    SpeechPipeline,
    SpeechPipelineError,
    SpeechProviderNotConfigured,
    SpeechSegment,
    normalise_language,
    normalise_transcript,
    normalise_translation,
    render_subtitles,
)


def transcript():
    return {"segments": [
        {"segmentId": "s1", "startMs": 0, "endMs": 1250, "text": "Ciao"},
        {"segmentId": "s2", "startMs": 1400, "endMs": 2600, "text": "Mondo", "speakerId": "speaker_1"},
    ]}


def test_language_normalisation_accepts_supported_regional_codes():
    assert normalise_language("it") == "it"
    assert normalise_language("en-us") == "en-US"
    assert normalise_language("zh-hans") == "zh-Hans"


@pytest.mark.parametrize("value", ["", "xx", "it-123", None, 42, "en<script>"])
def test_language_normalisation_rejects_invalid_or_unsupported_codes(value):
    with pytest.raises(SpeechPipelineError):
        normalise_language(value)


def test_transcript_preserves_ordered_timing_and_speaker_ids():
    segments = normalise_transcript(transcript(), 3000)
    assert segments == [
        SpeechSegment("s1", 0, 1250, "Ciao"),
        SpeechSegment("s2", 1400, 2600, "Mondo", "speaker_1"),
    ]


@pytest.mark.parametrize("duration", [0, -1, 86_400_001, True, "3000"])
def test_transcript_rejects_invalid_duration(duration):
    with pytest.raises(SpeechPipelineError):
        normalise_transcript(transcript(), duration)


@pytest.mark.parametrize("raw", [
    {"segments": []},
    {"segments": [{"segmentId": "../bad", "startMs": 0, "endMs": 1, "text": "x"}]},
    {"segments": [{"segmentId": "s1", "startMs": 2, "endMs": 1, "text": "x"}]},
    {"segments": [{"segmentId": "s1", "startMs": 0, "endMs": 4000, "text": "x"}]},
    {"segments": [{"segmentId": "s1", "startMs": 0, "endMs": 1, "text": " "}]},
    {"segments": [
        {"segmentId": "s1", "startMs": 0, "endMs": 1, "text": "x"},
        {"segmentId": "s1", "startMs": 2, "endMs": 3, "text": "y"},
    ]},
    {"segments": [
        {"segmentId": "s2", "startMs": 10, "endMs": 20, "text": "x"},
        {"segmentId": "s1", "startMs": 0, "endMs": 5, "text": "y"},
    ]},
])
def test_transcript_rejects_malformed_segments(raw):
    with pytest.raises(SpeechPipelineError):
        normalise_transcript(raw, 3000)


def test_translation_preserves_source_timing_and_speaker_attribution():
    source = normalise_transcript(transcript(), 3000)
    result = normalise_translation(source, {"segments": [
        {"segmentId": "s2", "text": "World"},
        {"segmentId": "s1", "text": "Hello"},
    ]}, "en")
    assert result == [
        SpeechSegment("s1", 0, 1250, "Hello"),
        SpeechSegment("s2", 1400, 2600, "World", "speaker_1"),
    ]


@pytest.mark.parametrize("raw", [
    {"segments": [{"segmentId": "s1", "text": "Hello"}]},
    {"segments": [{"segmentId": "s1", "text": "Hello"}, {"segmentId": "s1", "text": "Again"}]},
    {"segments": [{"segmentId": "s1", "text": "Hello"}, {"segmentId": "unknown", "text": "?"}]},
    {"segments": [{"segmentId": "s1", "text": " "}, {"segmentId": "s2", "text": "World"}]},
])
def test_translation_rejects_missing_duplicate_or_unknown_segments(raw):
    source = normalise_transcript(transcript(), 3000)
    with pytest.raises(SpeechPipelineError):
        normalise_translation(source, raw, "en")


def test_subtitle_export_supports_srt_and_webvtt_and_escapes_markup():
    segments = [SpeechSegment("s1", 3_723_004, 3_724_500, "A <b>test</b> --> ok")]
    srt = render_subtitles(segments, "srt")
    vtt = render_subtitles(segments, "vtt")
    assert "01:02:03,004 --> 01:02:04,500" in srt
    assert "&lt;b&gt;test&lt;/b&gt; —&gt; ok" in srt
    assert vtt.startswith("WEBVTT\n\n")
    assert "01:02:03.004 --> 01:02:04.500" in vtt


def test_subtitle_export_rejects_unsupported_format_and_empty_list():
    with pytest.raises(SpeechPipelineError):
        render_subtitles([], "srt")
    with pytest.raises(SpeechPipelineError):
        render_subtitles([SpeechSegment("s1", 0, 100, "Hello")], "ass")


class FakeProvider:
    def transcribe(self, asset_path, language=None):
        assert asset_path == "/safe/media.mp4"
        assert language == "it"
        return transcript()

    def translate(self, segments, target_language):
        assert target_language == "en"
        return {"segments": [{"segmentId": item["segmentId"], "text": "translated"}
                             for item in segments]}


def test_pipeline_fails_closed_without_provider():
    pipeline = SpeechPipeline()
    assert pipeline.configured is False
    with pytest.raises(SpeechProviderNotConfigured):
        pipeline.transcribe("/safe/media.mp4", 3000, "it")


def test_pipeline_uses_injected_provider_and_validates_every_response():
    pipeline = SpeechPipeline(FakeProvider())
    assert pipeline.configured is True
    source = pipeline.transcribe("/safe/media.mp4", 3000, "it")
    translated = pipeline.translate(source, "en")
    assert [segment.text for segment in translated] == ["translated", "translated"]
    assert [(segment.start_ms, segment.end_ms) for segment in translated] == [(0, 1250), (1400, 2600)]
