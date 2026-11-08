"""Integration test for rendering text overlays onto a video composition."""
import json, os, shutil, subprocess, tempfile, unittest, uuid
from pathlib import Path

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class TextOverlayRenderTest(unittest.TestCase):
    def test_text_overlay_creates_video_stream(self):
        root=tempfile.mkdtemp(prefix='editore_text_overlay_')
        previous=os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR']=root
            from backend import server
            server.ROOT=Path(root); server.ASSETS=server.ROOT/'assets'; server.OUTPUTS=server.ROOT/'outputs'
            server.ASSETS.mkdir(parents=True,exist_ok=True); server.OUTPUTS.mkdir(parents=True,exist_ok=True)
            base_id,job_id=(uuid.uuid4().hex for _ in range(2))
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=blue:s=320x180:d=1','-frames:v','1',str(server.ASSETS/f'{base_id}.png')],check=True,capture_output=True)
            project={'width':320,'height':180,'fps':24,'tracks':[
                {'kind':'video','clips':[{'kind':'image','assetId':base_id,'startMs':0,'durationMs':1000}]},
                {'kind':'text','clips':[{'kind':'text','text':'Prova testo','startMs':0,'durationMs':1000,'x':20,'y':20,'width':280,'height':80,'fontSize':36,'color':'#FFFFFF'}]}
            ]}
            server.jobs[job_id]={'state':'queued','progress':0.0,'message':'In coda'}
            server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[job_id]['state'],'completed',server.jobs[job_id])
            output=server.OUTPUTS/f'{job_id}.mp4'
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type,width,height','-of','json',str(output)],check=True,capture_output=True,text=True)
            streams=json.loads(probe.stdout)['streams']
            self.assertTrue(any(x['codec_type']=='video' for x in streams))
            frame=subprocess.run(['ffmpeg','-v','error','-i',str(output),'-frames:v','1','-f','rawvideo','-pix_fmt','rgb24','-'],check=True,capture_output=True)
            self.assertGreater(len(frame.stdout),0)
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR',None)
            else: os.environ['MEDIA_DATA_DIR']=previous
            shutil.rmtree(root,ignore_errors=True)

if __name__=='__main__': unittest.main()
