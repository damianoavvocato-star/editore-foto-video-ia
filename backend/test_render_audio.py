"""Integration regression test for mixed image/video + audio export.
Run: python -m unittest backend.test_render_audio
Requires FFmpeg and ffprobe on PATH.
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import uuid
from pathlib import Path


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class AudioRenderIntegrationTest(unittest.TestCase):
    def test_image_with_audio_track_exports_mp4_with_audio_stream(self):
        root = tempfile.mkdtemp(prefix='editore_backend_test_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        os.environ['MEDIA_DATA_DIR'] = root
        try:
            # Import after selecting an isolated data directory.
            from backend import server
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            image_id, audio_id, job_id = (uuid.uuid4().hex for _ in range(3))
            image_path = Path(root) / 'assets' / f'{image_id}.png'
            audio_path = Path(root) / 'assets' / f'{audio_id}.wav'
            subprocess.run([
                'ffmpeg', '-y', '-f', 'lavfi', '-i', 'color=c=blue:s=160x120:d=1',
                '-frames:v', '1', str(image_path)
            ], check=True, capture_output=True)
            subprocess.run([
                'ffmpeg', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
                '-c:a', 'pcm_s16le', str(audio_path)
            ], check=True, capture_output=True)
            server.jobs[job_id] = {'state': 'queued', 'progress': 0.0, 'message': 'In coda'}
            project = {'width': 160, 'height': 120, 'fps': 24, 'tracks': [
                {'kind': 'image', 'muted': False, 'clips': [
                    {'kind': 'image', 'assetId': image_id, 'startMs': 0, 'durationMs': 1000}
                ]},
                {'kind': 'audio', 'muted': False, 'clips': [
                    {'kind': 'audio', 'assetId': audio_id, 'startMs': 0, 'durationMs': 1000, 'volume': 0.7}
                ]},
            ]}
            server._render_job(job_id, project, {
                'resolution': 'p720', 'fps': 24, 'container': 'mp4',
                'codec': 'h264', 'includeAudio': True,
            })
            self.assertEqual(server.jobs[job_id]['state'], 'completed', server.jobs[job_id])
            output = next(server.OUTPUTS.glob(job_id + '.mp4'))
            probe = subprocess.run([
                'ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type,codec_name',
                '-of', 'json', str(output)
            ], check=True, capture_output=True, text=True)
            streams = json.loads(probe.stdout)['streams']
            self.assertTrue(any(stream['codec_type'] == 'video' for stream in streams))
            self.assertTrue(any(stream['codec_type'] == 'audio' for stream in streams))
        finally:
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()


def test_audio_clip_supports_source_offset_and_fades():
    """Audio clips accept source trim, fade-in and fade-out parameters."""
    import json, os, shutil, subprocess, tempfile, uuid
    from pathlib import Path
    from backend import server
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        import pytest; pytest.skip('FFmpeg/ffprobe required')
    root = Path(tempfile.mkdtemp(prefix='editore_audio_fades_'))
    old_root, old_assets, old_outputs = server.ROOT, server.ASSETS, server.OUTPUTS
    try:
        server.ROOT=root; server.ASSETS=root/'assets'; server.OUTPUTS=root/'outputs'
        server.ASSETS.mkdir(); server.OUTPUTS.mkdir()
        audio_id, image_id, job_id = uuid.uuid4().hex, uuid.uuid4().hex, uuid.uuid4().hex
        subprocess.run(['ffmpeg','-y','-f','lavfi','-i','sine=frequency=440:duration=3','-c:a','aac',str(server.ASSETS/f'{audio_id}.m4a')],check=True,capture_output=True)
        subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=blue:s=160x120:d=2','-frames:v','1',str(server.ASSETS/f'{image_id}.png')],check=True,capture_output=True)
        project={'width':160,'height':120,'tracks':[
            {'kind':'video','clips':[{'kind':'image','assetId':image_id,'durationMs':2000}]},
            {'kind':'audio','clips':[{'kind':'audio','assetId':audio_id,'durationMs':1800,'sourceStartMs':300,'startMs':100,'volume':0.7,'fadeInMs':250,'fadeOutMs':300}]}
        ]}
        server.jobs[job_id]={'state':'queued','progress':0,'message':'queued'}
        server.cancel_events[job_id]=__import__('threading').Event()
        server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','includeAudio':True})
        assert server.jobs[job_id]['state']=='completed', server.jobs[job_id]
        probe=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type','-of','json',str(server.OUTPUTS/f'{job_id}.mp4')],check=True,capture_output=True,text=True)
        assert any(x['codec_type']=='audio' for x in json.loads(probe.stdout)['streams'])
    finally:
        server.ROOT,server.ASSETS,server.OUTPUTS=old_root,old_assets,old_outputs
        shutil.rmtree(root,ignore_errors=True)
