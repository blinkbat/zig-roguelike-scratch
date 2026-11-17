from pathlib import Path
import tempfile
import unittest

from art_support import ROOT, arguments, aseprite, main


args, remaining = arguments()

PORTS = {
    'port_ground.lua': ('grass', 'local stamp=os.date', 320),
    'port_bridge.lua': ('bridge', 'local stamp=os.date', 320),
    'port_forest.lua': ('forest-tree-walls', 'local backup=', 448),
}


class InstallSourceTests(unittest.TestCase):
    def run_lua(self, script_path, **params):
        return aseprite(args.aseprite, script_path, params)

    def port(self, filename, blocked):
        name, start, height = PORTS[filename]
        source = (ROOT / 'tools/tile_art' / filename).read_text(encoding='utf-8')
        publication = source[source.index(start):source.index('atlas:saveAs(')]
        with tempfile.TemporaryDirectory(prefix='cistern-install-port-test-') as temporary:
            work = Path(temporary)
            working = work / 'working.aseprite'
            canonical = work / 'canonical.aseprite'
            if blocked:
                canonical.mkdir()
            script = work / 'publication.lua'
            script.write_text('''
local work=app.params.work..'/'
local backups=work
local path=app.params.source
local art_path=path
local canonical=app.params.canonical
local install=app.params.install=='yes'
local sourceFiles=dofile(app.params.helper)
local name=app.params.name
local title=name:gsub('^%l',string.upper)
local height=tonumber(app.params.height)
local original=Image(2,2,ColorMode.RGB)
original:clear(app.pixelColor.rgba(91,122,153,255))
local saved=Image(original)
local position=Point(3,67)
local extension=Image(512,height,ColorMode.RGB)
extension:putPixel(70,130,app.pixelColor.rgba(17,43,81,255))
local sheet=Image(extension)
local s=Sprite(512,height,ColorMode.RGB)
local sprite=s
local drawing=s.layers[1]
drawing.name='Draw here'
s:newCel(drawing,1,original,position)
s:saveAs(path)
''' + publication + '\nprint("PUBLICATION_COMPLETE")\n', encoding='utf-8')
            result = self.run_lua(script, work=work, source=working, canonical=canonical,
                                  helper=ROOT / 'tools/tile_art/source_files.lua',
                                  name=name, height=height, install='yes')
            output = result.stdout + result.stderr
            self.assertTrue(working.is_file(), output)
            self.assertTrue(any(work.glob('*before-*.aseprite')) or
                            any(work.glob('forest-tree-walls.*.aseprite')), output)
            if blocked:
                self.assertNotEqual(0, result.returncode, output)
                self.assertNotIn('PUBLICATION_COMPLETE', output)
                self.assertTrue(canonical.is_dir())
            else:
                self.assertEqual(0, result.returncode, output)
                self.assertIn('PUBLICATION_COMPLETE', output)
                self.assertEqual(working.read_bytes(), canonical.read_bytes())

    def test_each_port_propagates_failed_canonical_publication(self):
        for filename in PORTS:
            with self.subTest(script=filename):
                self.port(filename, blocked=True)

    def test_each_port_publishes_exact_verified_working_bytes(self):
        for filename in PORTS:
            with self.subTest(script=filename):
                self.port(filename, blocked=False)

    def tone(self, fail):
        with tempfile.TemporaryDirectory(prefix='cistern-install-tone-test-') as temporary:
            work = Path(temporary)
            for folder in ('assets/source', 'assets/walls', 'assets/ground', 'assets/backup', 'wall-mocks'):
                (work / folder).mkdir(parents=True)
            source = work / 'assets/source/forest-tree-walls.aseprite'
            desktop = work / 'desktop.aseprite'
            script = work / 'tone.lua'
            script.write_text('''
local root=app.params.root
local s=Sprite(2,2,ColorMode.RGB)
s.layers[1].name='Draw here'
local im=Image(2,2,ColorMode.RGB)
im:clear(app.pixelColor.rgba(107,185,112,255))
s:newCel(s.layers[1],1,im,Point(0,0))
s:saveAs(root..'assets/source/forest-tree-walls.aseprite')
s:saveCopyAs(app.params.desktop)
s:close()
im:saveAs(root..'assets/walls/forest-tree-walls.png')
im:saveAs(root..'assets/ground/grass.png')
local realapp,realio=app,io
local desktop=realapp.params.desktop
local customio=setmetatable({open=function(path,mode)
 if path==desktop then
  if mode=='wb' and realapp.params.fail=='yes' then return nil,'injected publication failure' end
  path=realapp.params.desktop
 end
 return realio.open(path,mode)
end},{__index=realio})
local env
env=setmetatable({
 io=customio,
 app={params=realapp.params,pixelColor=realapp.pixelColor,open=realapp.open,
  fs={tempPath=realapp.params.work,joinPath=realapp.fs.joinPath}},
 dofile=function(path)
  if path==root..'tools/tile_art/source_files.lua' then
   return assert(loadfile(realapp.params.helper,'t',env))()
  end
  assert(path==root..'tools/tile_art/export_forest.lua','Unexpected script')
 end,
},{__index=_G})
local input=assert(realio.open(realapp.params.script,'rb'))
local body=assert(input:read('*a')); assert(input:close())
local declaration="local desktop='C:/Users/DavidBennett/Desktop/forest-tree-walls.aseprite'"
local first,last=body:find(declaration,1,true)
assert(first,'Desktop declaration missing')
body=body:sub(1,first-1)..'local desktop='..string.format('%q',desktop)..body:sub(last+1)
assert(load(body,'@'..realapp.params.script,'t',env))()
''', encoding='utf-8')
            result = self.run_lua(script, root=work.as_posix() + '/', work=work,
                                  desktop=desktop, fail='yes' if fail else 'no',
                                  helper=ROOT / 'tools/tile_art/source_files.lua',
                                  script=ROOT / 'tools/tile_art/tone_forest.lua')
            output = result.stdout + result.stderr
            report = work / 'wall-mocks/forest-tone.txt'
            if fail:
                self.assertNotEqual(0, result.returncode, output)
                self.assertIn('injected publication failure', output)
                self.assertFalse(report.exists())
                self.assertNotEqual(source.read_bytes(), desktop.read_bytes())
                backups = list((work / 'assets/backup').glob('*.aseprite'))
                self.assertEqual(1, len(backups))
                self.assertEqual(desktop.read_bytes(), backups[0].read_bytes())
            else:
                self.assertEqual(0, result.returncode, output)
                self.assertTrue(report.is_file())
                self.assertEqual(source.read_bytes(), desktop.read_bytes())

    def test_tone_propagates_failed_desktop_publication(self):
        self.tone(fail=True)

    def test_tone_publishes_exact_verified_source_bytes(self):
        self.tone(fail=False)

    def new_sheet(self, blocked, trimmed=False):
        with tempfile.TemporaryDirectory(prefix='cistern-new-sheet-test-') as temporary:
            work = Path(temporary)
            template = work / 'template.aseprite'
            title = work / 'title.png'
            destination = work / 'new.aseprite'
            fixture = work / 'fixture.lua'
            fixture.write_text('''
local s=Sprite(512,320,ColorMode.RGB)
s.layers[1].name='Labels - hide before export'
local labels=Image(512,320,ColorMode.RGB)
labels:clear(app.pixelColor.rgba(40,50,60,255))
if app.params.trimmed=='yes' then
 labels=Image(12,80,ColorMode.RGB)
 labels:clear(app.pixelColor.rgba(40,50,60,255))
end
s:newCel(s.layers[1],1,labels,Point(0,0))
if app.params.trimmed=='yes' then s.layers[1]:cel(1).position=Point(12,8) end
local paint=s:newLayer(); paint.name='Draw here'
s:newCel(paint,1,labels,Point(0,0))
s:saveAs(app.params.template); s:close()
local title=Image(512,64,ColorMode.RGB)
title:putPixel(12,8,app.pixelColor.rgba(70,80,90,255))
title:putPixel(40,8,app.pixelColor.rgba(70,80,90,255))
title:saveAs(app.params.title)
''', encoding='utf-8')
            result = self.run_lua(fixture, template=template, title=title,
                                  trimmed='yes' if trimmed else 'no')
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            before = template.read_bytes()
            if blocked:
                destination.mkdir()
            result = self.run_lua(ROOT / 'tools/tile_art/new_sheet.lua',
                                  template=template, title=title, out=destination)
            self.assertEqual(before, template.read_bytes())
            if blocked:
                self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertTrue(destination.is_dir())
            else:
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertTrue(destination.is_file())
                fixture.write_text('''
local s=assert(app.open(app.params.out))
assert(s.width==512 and s.height==320 and #s.layers==2)
local cel=assert(s.layers[1]:cel(1))
local labels=Image(512,320,ColorMode.RGB)
labels:drawImage(cel.image,cel.position)
assert(labels:getPixel(12,8)==app.pixelColor.rgba(70,80,90,255))
assert(labels:getPixel(40,8)==app.pixelColor.rgba(70,80,90,255))
assert(app.pixelColor.rgbaA(labels:getPixel(13,9))==0)
assert(labels:getPixel(12,64)==app.pixelColor.rgba(40,50,60,255))
assert(s.layers[2]:cel(1).image:isEmpty())
s:close()
''', encoding='utf-8')
                result = self.run_lua(fixture, out=destination)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_new_sheet_rejects_blocked_destination(self):
        self.new_sheet(blocked=True)

    def test_new_sheet_saves_new_title_and_blank_paint(self):
        self.new_sheet(blocked=False)

    def test_new_sheet_replaces_title_beyond_trimmed_labels_bounds(self):
        self.new_sheet(blocked=False, trimmed=True)


if __name__ == '__main__':
    main(remaining)
