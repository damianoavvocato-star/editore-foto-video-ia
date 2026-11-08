"""Integration test for an image overlay composited over a base clip."""
import json, os, shutil, subprocess, tempfile, unittest, uuid
from pathlib import Path

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class OverlayRenderIntegrationTest(unittest.TestCase):
    def test_image_overlay_is_composited(self):
        root=tempfile.mkdtemp(prefix='editore_overlay_test_')
        previous=os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR']=root
            from backend import server
            server.ROOT=Path(root); server.ASSETS=server.ROOT/'assets'; server.OUTPUTS=server.ROOT/'outputs'
            server.ASSETS.mkdir(parents=True,exist_ok=True); server.OUTPUTS.mkdir(parents=True,exist_ok=True)
            base_id, overlay_id, job_id=(uuid.uuid4().hex for _ in range(3))
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=blue:s=160x120:d=1','-frames:v','1',str(server.ASSETS/f'{base_id}.png')],check=True,capture_output=True)
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=red:s=40x40:d=1','-frames:v','1',str(server.ASSETS/f'{overlay_id}.png')],check=True,capture_output=True)
            server.jobs[job_id]={'state':'queued','progress':0.0,'message':'In coda'}
            project={'width':160,'height':120,'fps':24,'tracks':[
                {'kind':'video','clips':[{'kind':'image','assetId':base_id,'startMs':0,'durationMs':1000}]},
                {'kind':'overlay','clips':[{'kind':'image','assetId':overlay_id,'startMs':0,'durationMs':1000,'x':10,'y':10,'width':40,'height':40,'opacity':1.0}]}
            ]}
            server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[job_id]['state'],'completed',server.jobs[job_id])
            output=next(server.OUTPUTS.glob(job_id+'.mp4'))
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type','-of','json',str(output)],check=True,capture_output=True,text=True)
            self.assertTrue(any(x['codec_type']=='video' for x in json.loads(probe.stdout)['streams']))
            frame=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'],check=True,capture_output=True)
            self.assertGreater(len(frame.stdout),0)
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR',None)
            else: os.environ['MEDIA_DATA_DIR']=previous
            shutil.rmtree(root,ignore_errors=True)

if __name__=='__main__': unittest.main()
