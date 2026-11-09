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
            from PIL import Image, ImageDraw
            overlay_image=Image.new('RGBA',(80,60),(0,0,0,0))
            ImageDraw.Draw(overlay_image).rectangle((20,15,59,44),fill=(255,255,0,255))
            overlay_image.save(server.ASSETS/f'{overlay_id}.png')
            server.jobs[job_id]={'state':'queued','progress':0.0,'message':'queued'}
            project={'width':320,'height':180,'fps':24,'tracks':[
                {'kind':'video','clips':[{'kind':'image','assetId':base_id,'durationMs':1000,'colorGrade':{'exposure':0.25,'contrast':1.1,'saturation':1.2,'temperature':18,'tint':-8,'highlights':0.15,'shadows':-0.1},'keyframes':[{'timeMs':0,'property':'scale','value':1.0},{'timeMs':900,'property':'scale','value':1.25},{'timeMs':0,'property':'positionX','value':0.0},{'timeMs':900,'property':'positionX','value':20.0},{'timeMs':0,'property':'positionY','value':0.0},{'timeMs':900,'property':'positionY','value':-10.0},{'timeMs':0,'property':'rotation','value':0.0},{'timeMs':900,'property':'rotation','value':12.0},{'timeMs':0,'property':'opacity','value':0.7},{'timeMs':900,'property':'opacity','value':1.0}] }]},
                {'kind':'overlay','clips':[{'kind':'image','assetId':overlay_id,'durationMs':1000,'x':30,'y':30,'width':80,'height':60,'rotationDegrees':8,'fadeInMs':150,'fadeOutMs':150,'keyframes':[{'timeMs':0,'property':'scale','value':1.0},{'timeMs':900,'property':'scale','value':1.3},{'timeMs':0,'property':'positionX','value':0.0},{'timeMs':900,'property':'positionX','value':30.0},{'timeMs':0,'property':'positionY','value':0.0},{'timeMs':900,'property':'positionY','value':15.0},{'timeMs':0,'property':'rotation','value':0.0},{'timeMs':900,'property':'rotation','value':20.0},{'timeMs':0,'property':'opacity','value':0.5},{'timeMs':900,'property':'opacity','value':1.0}]}]}
            ]}
            server._render_job(job_id,project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[job_id]['state'],'completed',server.jobs[job_id])
            output=server.OUTPUTS/f'{job_id}.mp4'
            probe=subprocess.run(['ffprobe','-v','error','-show_entries','stream=codec_type,duration','-of','json',str(output)],check=True,capture_output=True,text=True)
            self.assertTrue(any(x['codec_type']=='video' for x in json.loads(probe.stdout)['streams']))

            # Transparent pixels in the PNG must reveal the graded base clip.
            alpha_frame = Path(root) / 'alpha-check.png'
            subprocess.run(
                ['ffmpeg', '-y', '-ss', '0.25', '-i', str(output),
                 '-frames:v', '1', str(alpha_frame)],
                check=True, capture_output=True,
            )
            alpha_image = Image.open(alpha_frame).convert('RGB')
            transparent_pixel = alpha_image.getpixel((42, 38))
            base_pixel = alpha_image.getpixel((10, 10))
            self.assertLess(
                sum(abs(a-b) for a, b in zip(transparent_pixel, base_pixel)), 45,
                f'Area PNG trasparente non mostra correttamente la clip sottostante: {transparent_pixel} vs {base_pixel}',
            )

            # Verify that animated overlay position changes in the actual
            # encoded output, rather than merely accepting a valid FFmpeg graph.
            from PIL import Image
            centers = []
            for sample, timestamp in [('early', '0.25'), ('late', '0.80')]:
                frame = work_frame = Path(root) / f'{sample}.png'
                subprocess.run(
                    ['ffmpeg', '-y', '-ss', timestamp, '-i', str(output),
                     '-frames:v', '1', str(frame)],
                    check=True, capture_output=True,
                )
                image = Image.open(frame).convert('RGB')
                yellow = [
                    (x, y)
                    for y in range(image.height)
                    for x in range(image.width)
                    if (lambda p: p[0] > 80 and p[1] > 80 and p[2] < 100)(image.getpixel((x, y)))
                ]
                self.assertGreater(len(yellow), 20, f'Overlay giallo non visibile a {timestamp}s')
                centers.append((
                    sum(point[0] for point in yellow) / len(yellow),
                    sum(point[1] for point in yellow) / len(yellow),
                ))
            self.assertGreater(
                centers[1][0], centers[0][0] + 10,
                f'Keyframe posizione X non applicato: {centers}',
            )
        finally:
            if previous is None: os.environ.pop('MEDIA_DATA_DIR',None)
            else: os.environ['MEDIA_DATA_DIR']=previous
            shutil.rmtree(root,ignore_errors=True)


    def test_keyframe_expression_interpolates_and_rejects_out_of_range_values(self):
        from backend.server import _keyframe_expression
        points = [
            {'timeMs': 0, 'property': 'scale', 'value': 1.0},
            {'timeMs': 1000, 'property': 'scale', 'value': 2.0},
        ]
        expression = _keyframe_expression(points, 'scale', 't')
        self.assertIn('if(lt(t,1.000000)', expression)
        self.assertIn('(t-0.000000)/1.000000', expression)
        with self.assertRaises(RuntimeError):
            _keyframe_expression(
                [{'timeMs': 0, 'property': 'opacity', 'value': 1.5}],
                'opacity',
                'T',
            )

if __name__=='__main__': unittest.main()
