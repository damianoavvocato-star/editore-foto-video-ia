"""Integration test for two image clips joined with an FFmpeg crossfade."""
import json, os, shutil, subprocess, tempfile, unittest, uuid
from pathlib import Path

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class TransitionRenderIntegrationTest(unittest.TestCase):
    def test_two_images_with_fade_export_video(self):
        root=tempfile.mkdtemp(prefix='editore_transition_test_')
        previous=os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR']=root
            from backend import server
            server.ROOT=Path(root); server.ASSETS=server.ROOT/'assets'; server.OUTPUTS=server.ROOT/'outputs'
            server.ASSETS.mkdir(parents=True,exist_ok=True); server.OUTPUTS.mkdir(parents=True,exist_ok=True)
            ids=[uuid.uuid4().hex for _ in range(3)]
            for asset_id, color in zip(ids[:2], ('red','blue')):
                subprocess.run(['ffmpeg','-y','-f','lavfi','-i',f'color=c={color}:s=160x120:d=1','-frames:v','1',str(Path(root)/'assets'/f'{asset_id}.png')],check=True,capture_output=True)
            job_id=ids[2]
            server.jobs[job_id]={'state':'queued','progress':0.0,'message':'In coda'}
            project={'width':160,'height':120,'fps':24,'tracks':[{'kind':'video','clips':[
                {'kind':'image','assetId':ids[0],'startMs':0,'durationMs':1000,'transitionAfterMs':300,'transitionAfter':'fade'},
                {'kind':'image','assetId':ids[1],'startMs':1000,'durationMs':1000},
            ]}]}
            server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[job_id]['state'],'completed',server.jobs[job_id])
            output=next(server.OUTPUTS.glob(job_id+'.mp4'))
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_type','-of','json',str(output)],check=True,capture_output=True,text=True)
            data=json.loads(probe.stdout)
            self.assertTrue(any(x['codec_type']=='video' for x in data['streams']))
            self.assertGreater(float(data['format']['duration']),1.6)
            self.assertLess(float(data['format']['duration']),2.1)
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR',None)
            else: os.environ['MEDIA_DATA_DIR']=previous
            shutil.rmtree(root,ignore_errors=True)

if __name__=='__main__': unittest.main()
