"""Integration tests for clip color controls and animated overlay fades."""
import json, os, shutil, subprocess, tempfile, unittest, uuid
from pathlib import Path

@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'FFmpeg/ffprobe required')
class RenderEffectsTest(unittest.TestCase):
    def test_color_adjustment_and_overlay_fades_render(self):
        root=tempfile.mkdtemp(prefix='editore_effects_')
        previous=os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR']=root
            from backend import server
            server.ROOT=Path(root); server.ASSETS=server.ROOT/'assets'; server.OUTPUTS=server.ROOT/'outputs'
            server.ASSETS.mkdir(parents=True,exist_ok=True); server.OUTPUTS.mkdir(parents=True,exist_ok=True)
            base_id, overlay_id, job_id=(uuid.uuid4().hex for _ in range(3))
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=navy:s=320x180:d=1','-frames:v','1',str(server.ASSETS/f'{base_id}.png')],check=True,capture_output=True)
            subprocess.run(['ffmpeg','-y','-f','lavfi','-i','color=c=yellow:s=80x60:d=1','-frames:v','1',str(server.ASSETS/f'{overlay_id}.png')],check=True,capture_output=True)
            server.jobs[job_id]={'state':'queued','progress':0.0,'message':'queued'}
            project={'width':320,'height':180,'fps':24,'tracks':[
                {'kind':'video','clips':[{'kind':'image','assetId':base_id,'durationMs':1000,'colorGrade':{'exposure':0.25,'contrast':1.1,'saturation':1.2,'temperature':18,'tint':-8,'highlights':0.15,'shadows':-0.1}}]},
                {'kind':'overlay','clips':[{'kind':'image','assetId':overlay_id,'durationMs':1000,'x':30,'y':30,'width':80,'height':60,'rotationDegrees':8,'fadeInMs':150,'fadeOutMs':150}]}
            ]}
            server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[job_id]['state'],'completed',server.jobs[job_id])
            output=server.OUTPUTS/f'{job_id}.mp4'
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type,duration','-of','json',str(output)],check=True,capture_output=True,text=True)
            self.assertTrue(any(x['codec_type']=='video' for x in json.loads(probe.stdout)['streams']))
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR',None)
            else: os.environ['MEDIA_DATA_DIR']=previous
            shutil.rmtree(root,ignore_errors=True)

if __name__=='__main__': unittest.main()
