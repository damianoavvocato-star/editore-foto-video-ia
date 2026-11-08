"""Smoke integration tests for container formats supported by the renderer."""
import json, os, shutil, subprocess, tempfile, unittest, uuid
from pathlib import Path

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class ExportFormatTest(unittest.TestCase):
    def test_mp4_mov_avi_and_webm_containers(self):
        root = tempfile.mkdtemp(prefix='editore_formats_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            asset_id, job_id = uuid.uuid4().hex, uuid.uuid4().hex
            source = server.ASSETS / f'{asset_id}.png'
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=green:s=160x120:d=1','-frames:v','1',str(source)], check=True, capture_output=True)
            project = {'width':160,'height':120,'fps':24,'tracks':[{'kind':'video','clips':[{'kind':'image','assetId':asset_id,'startMs':0,'durationMs':1000}]}]}
            for container in ('mp4', 'mov', 'avi', 'webm'):
                current_job = uuid.uuid4().hex
                server.jobs[current_job] = {'state':'queued','progress':0.0,'message':'queued'}
                codec = 'vp9' if container == 'webm' else 'h264'
                server._render_job(current_job, project, {'resolution':'p720','fps':24,'container':container,'codec':codec,'includeAudio':False})
                self.assertEqual(server.jobs[current_job]['state'], 'completed', server.jobs[current_job])
                output = server.OUTPUTS / f'{current_job}.{container}'
                probe = subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type','-of','json',str(output)],check=True,capture_output=True,text=True)
                streams = json.loads(probe.stdout)['streams']
                self.assertTrue(any(stream['codec_type'] == 'video' for stream in streams), container)
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR', None)
            else: os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

if __name__ == '__main__': unittest.main()
