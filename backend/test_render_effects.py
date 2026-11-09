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
                {'kind':'video','clips':[{'kind':'image','assetId':base_id,'durationMs':1000,'colorGrade':{'exposure':0.25,'contrast':1.1,'saturation':1.2,'temperature':18,'tint':-8,'highlights':0.15,'shadows':-0.1},'keyframes':[{'timeMs':0,'property':'scale','value':1.0},{'timeMs':900,'property':'scale','value':1.25},{'timeMs':0,'property':'positionX','value':0.0},{'timeMs':900,'property':'positionX','value':20.0},{'timeMs':0,'property':'positionY','value':0.0},{'timeMs':900,'property':'positionY','value':-10.0},{'timeMs':0,'property':'rotation','value':0.0},{'timeMs':900,'property':'rotation','value':12.0},] }]},
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

            # Render the identical base clip without overlays as a pixel-level
            # reference; this avoids assuming that every canvas corner is visible
            # after rotation/cropping.
            baseline_job = uuid.uuid4().hex
            server.jobs[baseline_job]={'state':'queued','progress':0.0,'message':'queued'}
            baseline_project={'width':320,'height':180,'fps':24,'tracks':[project['tracks'][0]]}
            server._render_job(baseline_job,baseline_project,{'resolution':'p720','fps':24,'container':'mp4','codec':'h264','includeAudio':False})
            self.assertEqual(server.jobs[baseline_job]['state'],'completed',server.jobs[baseline_job])
            baseline_output=server.OUTPUTS/f'{baseline_job}.mp4'
            baseline_frame=Path(root)/'baseline.png'
            subprocess.run(
                ['ffmpeg','-y','-ss','0.25','-i',str(baseline_output),
                 '-frames:v','1',str(baseline_frame)],
                check=True,capture_output=True,
            )
            base_pixel=Image.open(baseline_frame).convert('RGB').getpixel((42,38))
            self.assertLess(
                sum(abs(a-b) for a,b in zip(transparent_pixel,base_pixel)), 45,
                f'Area PNG trasparente non coincide con la clip sottostante: {transparent_pixel} vs {base_pixel}',
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


    def test_primary_clip_opacity_composites_over_lower_video_track(self):
        root = tempfile.mkdtemp(prefix='editore_alpha_tracks_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            from PIL import Image
            lower_id, upper_id, overlay_id, job_id = (uuid.uuid4().hex for _ in range(4))
            Image.new('RGB', (160, 90), (220, 20, 20)).save(server.ASSETS / f'{lower_id}.png')
            Image.new('RGB', (160, 90), (20, 210, 30)).save(server.ASSETS / f'{upper_id}.png')
            Image.new('RGBA', (24, 24), (20, 40, 230, 255)).save(server.ASSETS / f'{overlay_id}.png')
            server.jobs[job_id] = {'state': 'queued', 'progress': 0.0, 'message': 'queued'}
            project = {
                'width': 160, 'height': 90, 'fps': 24,
                'tracks': [
                    {'kind': 'video', 'clips': [
                        {'kind': 'image', 'assetId': lower_id, 'startMs': 0, 'durationMs': 1000},
                    ]},
                    {'kind': 'video', 'clips': [
                        {'kind': 'image', 'assetId': upper_id, 'startMs': 0, 'durationMs': 1000,
                         'keyframes': [
                             {'timeMs': 0, 'property': 'opacity', 'value': 0.0},
                             {'timeMs': 500, 'property': 'opacity', 'value': 1.0},
                         ]},
                    ]},
                    {'kind': 'overlay', 'clips': [
                        {'kind': 'image', 'assetId': overlay_id, 'startMs': 0,
                         'durationMs': 1000, 'x': 0, 'y': 0, 'width': 24, 'height': 24},
                    ]},
                ],
            }
            server._render_job(job_id, project, {
                'resolution': 'p720', 'fps': 24, 'container': 'mp4',
                'codec': 'h264', 'includeAudio': False,
            })
            self.assertEqual(server.jobs[job_id]['state'], 'completed', server.jobs[job_id])
            output = server.OUTPUTS / f'{job_id}.mp4'
            samples = []
            for label, timestamp in [('early', '0.05'), ('late', '0.80')]:
                frame = Path(root) / f'{label}.png'
                subprocess.run(
                    ['ffmpeg', '-y', '-ss', timestamp, '-i', str(output),
                     '-frames:v', '1', str(frame)],
                    check=True, capture_output=True,
                )
                samples.append(Image.open(frame).convert('RGB').getpixel((80, 45)))
            self.assertGreater(samples[0][0], samples[0][1] * 2,
                               f'La clip inferiore non è visibile durante la dissolvenza: {samples[0]}')
            self.assertGreater(samples[1][1], samples[1][0] * 2,
                               f'La clip superiore non è diventata opaca: {samples[1]}')
            overlay_frame = Path(root) / 'overlay-after-alpha.png'
            subprocess.run(
                ['ffmpeg', '-y', '-ss', '0.80', '-i', str(output),
                 '-frames:v', '1', str(overlay_frame)],
                check=True, capture_output=True,
            )
            overlay_pixel = Image.open(overlay_frame).convert('RGB').getpixel((8, 8))
            self.assertGreater(overlay_pixel[2], overlay_pixel[1] * 2,
                               f'Overlay perso nel percorso alpha: {overlay_pixel}')
        finally:
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

    def test_primary_alpha_composite_preserves_absolute_clip_start(self):
        root = tempfile.mkdtemp(prefix='editore_alpha_timing_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            from PIL import Image
            asset_id, job_id = (uuid.uuid4().hex for _ in range(2))
            Image.new('RGB', (160, 90), (210, 30, 20)).save(server.ASSETS / f'{asset_id}.png')
            server.jobs[job_id] = {'state': 'queued', 'progress': 0.0, 'message': 'queued'}
            project = {
                'width': 160, 'height': 90, 'fps': 24,
                'tracks': [{
                    'kind': 'video',
                    'clips': [{
                        'kind': 'image', 'assetId': asset_id,
                        'startMs': 500, 'durationMs': 1000,
                        'keyframes': [
                            {'timeMs': 0, 'property': 'opacity', 'value': 0.0},
                            {'timeMs': 500, 'property': 'opacity', 'value': 1.0},
                        ],
                    }],
                }],
            }
            server._render_job(job_id, project, {
                'resolution': 'p720', 'fps': 24, 'container': 'mp4',
                'codec': 'h264', 'includeAudio': False,
            })
            self.assertEqual(server.jobs[job_id]['state'], 'completed', server.jobs[job_id])
            output = server.OUTPUTS / f'{job_id}.mp4'
            samples = []
            for label, timestamp in [('gap', '0.20'), ('visible', '1.20')]:
                frame = Path(root) / f'{label}.png'
                subprocess.run(
                    ['ffmpeg', '-y', '-ss', timestamp, '-i', str(output),
                     '-frames:v', '1', str(frame)],
                    check=True, capture_output=True,
                )
                samples.append(Image.open(frame).convert('RGB').getpixel((80, 45)))
            self.assertLess(max(samples[0]), 35,
                            f'La clip è visibile prima del suo startMs: {samples[0]}')
            self.assertGreater(samples[1][0], samples[1][1] * 2,
                               f'La clip non è visibile dopo il suo startMs: {samples[1]}')
        finally:
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

    def test_alpha_multitrack_path_rejects_unsupported_wipe_transition(self):
        from backend import server

        project = {
            'tracks': [{
                'kind': 'video',
                'clips': [
                    {'startMs': 0, 'durationMs': 1000, 'transitionAfterMs': 250,
                     'transitionAfter': 'radialwipe'},
                    {'startMs': 1000, 'durationMs': 1000},
                ],
            }],
        }
        with self.assertRaisesRegex(RuntimeError, 'non ancora supportata'):
            server._render_primary_alpha_layers(
                'a' * 32, project, {}, Path(tempfile.gettempdir()),
                320, 180, 24,
            )

    def test_alpha_multitrack_fade_transition_blends_adjacent_clips(self):
        root = tempfile.mkdtemp(prefix='editore_alpha_transition_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        previous_server_paths = None
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            previous_server_paths = (server.ROOT, server.ASSETS, server.OUTPUTS)
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            from PIL import Image
            first_id, second_id, job_id = (uuid.uuid4().hex for _ in range(3))
            Image.new('RGB', (160, 90), (220, 20, 20)).save(server.ASSETS / f'{first_id}.png')
            Image.new('RGB', (160, 90), (20, 210, 30)).save(server.ASSETS / f'{second_id}.png')
            server.jobs[job_id] = {'state': 'queued', 'progress': 0.0, 'message': 'queued'}
            project = {
                'width': 160, 'height': 90, 'fps': 24,
                'tracks': [{
                    'kind': 'video',
                    'clips': [
                        {'kind': 'image', 'assetId': first_id, 'startMs': 0,
                         'durationMs': 1000, 'transitionAfterMs': 400,
                         'transitionAfter': 'fade',
                         'keyframes': [{'timeMs': 0, 'property': 'opacity', 'value': 1.0}]},
                        {'kind': 'image', 'assetId': second_id, 'startMs': 1000,
                         'durationMs': 1000},
                    ],
                }],
            }
            server._render_job(job_id, project, {
                'resolution': 'p720', 'fps': 24, 'container': 'mp4',
                'codec': 'h264', 'includeAudio': False,
            })
            self.assertEqual(server.jobs[job_id]['state'], 'completed', server.jobs[job_id])
            output = server.OUTPUTS / f'{job_id}.mp4'
            frame = Path(root) / 'transition-midpoint.png'
            subprocess.run(
                ['ffmpeg', '-y', '-ss', '0.80', '-i', str(output),
                 '-frames:v', '1', str(frame)],
                check=True, capture_output=True,
            )
            red, green, _blue = Image.open(frame).convert('RGB').getpixel((80, 45))
            self.assertGreater(red, 80, f'La clip uscente non partecipa alla dissolvenza: {red, green}')
            self.assertGreater(green, 80, f'La clip entrante non partecipa alla dissolvenza: {red, green}')
            self.assertLess(abs(red - green), 55,
                            f'La dissolvenza non miscela correttamente i due colori: {red, green}')
        finally:
            if previous_server_paths is not None:
                server.ROOT, server.ASSETS, server.OUTPUTS = previous_server_paths
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

    def test_alpha_multitrack_spatial_transitions_reveal_in_expected_direction(self):
        root = tempfile.mkdtemp(prefix='editore_alpha_spatial_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        previous_server_paths = None
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            previous_server_paths = (server.ROOT, server.ASSETS, server.OUTPUTS)
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            from PIL import Image
            first_id, second_id = uuid.uuid4().hex, uuid.uuid4().hex
            Image.new('RGB', (160, 90), (220, 20, 20)).save(server.ASSETS / f'{first_id}.png')
            Image.new('RGB', (160, 90), (20, 210, 30)).save(server.ASSETS / f'{second_id}.png')

            # p720 output is 1280x720; sample both sides of the
            # transition front, not merely the tiny source-image coordinates.
            samples = {
                'wipeleft': ((20, 360), (1200, 360)),
                'wiperight': ((1200, 360), (20, 360)),
                'slideleft': ((1000, 360), (200, 360)),
                'slideright': ((200, 360), (1000, 360)),
            }
            for transition_type, (green_point, red_point) in samples.items():
                with self.subTest(transition=transition_type):
                    job_id = uuid.uuid4().hex
                    server.jobs[job_id] = {
                        'state': 'queued', 'progress': 0.0, 'message': 'queued',
                    }
                    project = {
                        'width': 160, 'height': 90, 'fps': 24,
                        'tracks': [{
                            'kind': 'video',
                            'clips': [
                                {
                                    'kind': 'image', 'assetId': first_id,
                                    'startMs': 0, 'durationMs': 1000,
                                    'transitionAfterMs': 400,
                                    'transitionAfter': transition_type,
                                    'keyframes': [{
                                        'timeMs': 0, 'property': 'opacity', 'value': 1.0,
                                    }],
                                },
                                {
                                    'kind': 'image', 'assetId': second_id,
                                    'startMs': 1000, 'durationMs': 1000,
                                },
                            ],
                        }],
                    }
                    server._render_job(job_id, project, {
                        'resolution': 'p720', 'fps': 24,
                        'container': 'mp4', 'codec': 'h264',
                        'includeAudio': False,
                    })
                    self.assertEqual(
                        server.jobs[job_id]['state'], 'completed',
                        f'{transition_type}: {server.jobs[job_id]}',
                    )
                    frame = Path(root) / f'{transition_type}.png'
                    subprocess.run(
                        ['ffmpeg', '-y', '-ss', '0.80', '-i',
                         str(server.OUTPUTS / f'{job_id}.mp4'),
                         '-frames:v', '1', str(frame)],
                        check=True, capture_output=True,
                    )
                    image = Image.open(frame).convert('RGB')
                    green = image.getpixel(green_point)
                    red = image.getpixel(red_point)
                    self.assertGreater(
                        green[1], green[0] * 2,
                        f'{transition_type}: direzione entrante errata nel punto {green_point}: {green}',
                    )
                    self.assertGreater(
                        red[0], red[1] * 2,
                        f'{transition_type}: la clip uscente dovrebbe restare visibile in {red_point}: {red}',
                    )
        finally:
            if previous_server_paths is not None:
                server.ROOT, server.ASSETS, server.OUTPUTS = previous_server_paths
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

    def test_alpha_transition_keeps_overlay_and_audio_in_final_export(self):
        root = tempfile.mkdtemp(prefix='editore_alpha_av_')
        previous = os.environ.get('MEDIA_DATA_DIR')
        previous_server_paths = None
        try:
            os.environ['MEDIA_DATA_DIR'] = root
            from backend import server
            previous_server_paths = (server.ROOT, server.ASSETS, server.OUTPUTS)
            server.ROOT = Path(root)
            server.ASSETS = server.ROOT / 'assets'
            server.OUTPUTS = server.ROOT / 'outputs'
            server.ASSETS.mkdir(parents=True, exist_ok=True)
            server.OUTPUTS.mkdir(parents=True, exist_ok=True)
            from PIL import Image

            first_id, second_id, overlay_id, audio_id, job_id = (
                uuid.uuid4().hex for _ in range(5)
            )
            Image.new('RGB', (160, 90), (220, 20, 20)).save(
                server.ASSETS / f'{first_id}.png'
            )
            Image.new('RGB', (160, 90), (20, 210, 30)).save(
                server.ASSETS / f'{second_id}.png'
            )
            Image.new('RGBA', (24, 24), (20, 40, 230, 255)).save(
                server.ASSETS / f'{overlay_id}.png'
            )
            audio_path = server.ASSETS / f'{audio_id}.wav'
            subprocess.run(
                [server.FFMPEG, '-y', '-f', 'lavfi', '-i',
                 'sine=frequency=440:duration=1.2', '-c:a', 'pcm_s16le',
                 str(audio_path)],
                check=True, capture_output=True,
            )
            server.jobs[job_id] = {
                'state': 'queued', 'progress': 0.0, 'message': 'queued',
            }
            project = {
                'width': 160, 'height': 90, 'fps': 24,
                'tracks': [
                    {'kind': 'video', 'clips': [
                        {
                            'kind': 'image', 'assetId': first_id,
                            'startMs': 0, 'durationMs': 1000,
                            'transitionAfterMs': 400, 'transitionAfter': 'fade',
                            'keyframes': [
                                {'timeMs': 0, 'property': 'opacity', 'value': 1.0},
                            ],
                        },
                        {
                            'kind': 'image', 'assetId': second_id,
                            'startMs': 1000, 'durationMs': 1000,
                        },
                    ]},
                    {'kind': 'audio', 'clips': [{
                        'kind': 'audio', 'assetId': audio_id,
                        'startMs': 0, 'durationMs': 1200, 'volume': 0.8,
                    }]},
                    {'kind': 'overlay', 'clips': [{
                        'kind': 'image', 'assetId': overlay_id,
                        'startMs': 0, 'durationMs': 1200,
                        'x': 0, 'y': 0, 'width': 24, 'height': 24,
                    }]},
                ],
            }
            server._render_job(job_id, project, {
                'resolution': 'p720', 'fps': 24, 'container': 'mp4',
                'codec': 'h264', 'includeAudio': True,
            })
            self.assertEqual(
                server.jobs[job_id]['state'], 'completed', server.jobs[job_id],
            )
            output = server.OUTPUTS / f'{job_id}.mp4'
            audio_probe = subprocess.run(
                ['ffprobe', '-v', 'error', '-select_streams', 'a:0',
                 '-show_entries', 'stream=codec_name', '-of',
                 'default=noprint_wrappers=1:nokey=1', str(output)],
                check=True, capture_output=True, text=True,
            ).stdout.strip()
            self.assertEqual(audio_probe, 'aac', 'Traccia audio assente dall’export alpha')
            frame = Path(root) / 'alpha-with-overlay.png'
            subprocess.run(
                [server.FFMPEG, '-y', '-ss', '0.80', '-i', str(output),
                 '-frames:v', '1', str(frame)],
                check=True, capture_output=True,
            )
            overlay_pixel = Image.open(frame).convert('RGB').getpixel((8, 8))
            self.assertGreater(
                overlay_pixel[2], overlay_pixel[1] * 2,
                f'Overlay non conservato nel percorso alpha con audio: {overlay_pixel}',
            )
        finally:
            if previous_server_paths is not None:
                server.ROOT, server.ASSETS, server.OUTPUTS = previous_server_paths
            if previous is None:
                os.environ.pop('MEDIA_DATA_DIR', None)
            else:
                os.environ['MEDIA_DATA_DIR'] = previous
            shutil.rmtree(root, ignore_errors=True)

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
