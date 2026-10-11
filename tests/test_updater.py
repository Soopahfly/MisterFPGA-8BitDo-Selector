"""Run the real program updater with isolated installs and mocked HTTPS downloads."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT=Path(__file__).resolve().parents[1]
FILES=('Scripts/8BitDo_Controller_Selector.sh', 'Scripts/.8bitdo-selector/controller-menu')
LEGACY='Scripts/8BitDo_Selector_Update.sh'
PACKAGE_FILES=FILES+(LEGACY,)

class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)
        self.root=self.base/'fat'
        self.root.mkdir()
        subprocess.run(['bash',str(PROJECT/'install.sh')],
                       env=os.environ|{'MISTER_ROOT':str(self.root)},capture_output=True,check=True)
        profile=self.root/'config/8bitdo-profiles/xinput/xbox/input_2dc8_3106_v3.map'
        profile.write_bytes(b'custom-profile'.ljust(128,b'!'))
        inputs=self.root/'config/inputs'
        inputs.mkdir()
        (inputs/'input_2dc8_3106_v3.map').write_bytes(b'active'.ljust(128,b'?'))
        state=self.root/'config/8bitdo-profiles/xinput'
        (state/'last-selected').write_text('xbox\n')
        (state/'last-backup').write_text('backup-test\n')
        self.snapshot={str(p.relative_to(self.root)):p.read_bytes() for p in self.root.rglob('*')
                       if p.is_file() and (p.suffix=='.map' or p.name in ('last-selected','last-backup'))}
        # Force a real update, with a valid previous selector for rollback.
        (self.root/FILES[0]).write_text('#!/bin/bash\nprintf "old version\\n"\n')
        self.env=os.environ|{'MISTER_ROOT':str(self.root),'UPDATE_SOURCE_DIR':str(PROJECT)}

    def update(self, success=True, env=None, installer=False):
        args=['bash',str(PROJECT/('install.sh' if installer else FILES[0]))]
        args+=['--program-only'] if installer else ['update','--no-pause']
        result=subprocess.run(args,env=self.env|(env or {}),capture_output=True,text=True)
        self.assertEqual(result.returncode==0,success,result.stdout+result.stderr)
        for name,data in self.snapshot.items():
            self.assertEqual((self.root/name).read_bytes(),data,name)
        self.assertFalse((self.root/'config/8bitdo-profiles/.selector-lock').exists())
        return result

    def test_program_only_install_preserves_custom_profiles_and_active_maps(self):
        self.update(installer=True)
        for name in FILES:
            self.assertEqual((self.root/name).read_bytes(),(PROJECT/name).read_bytes())
            self.assertTrue(os.access(self.root/name,os.X_OK))
        backups=list((self.root/'config/8bitdo-profiles').glob('program-backup-*'))
        self.assertEqual(len(backups),1)
        self.assertIn(b'old version',(backups[0]/FILES[0]).read_bytes())

    def test_already_current_does_not_create_more_backups(self):
        self.update()
        before=set((self.root/'config/8bitdo-profiles').glob('program-backup-*'))
        self.assertIn('Already up to date',self.update().stdout)
        self.assertEqual(before,set((self.root/'config/8bitdo-profiles').glob('program-backup-*')))

    def test_existing_lock_is_not_removed_or_bypassed(self):
        lock=self.root/'config/8bitdo-profiles/.selector-lock'
        lock.mkdir()
        before={name:(self.root/name).read_bytes() for name in FILES}
        result=subprocess.run(['bash',str(PROJECT/FILES[0]),'update','--no-pause'],
                              env=self.env,capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('another updater is running',result.stderr)
        self.assertTrue(lock.is_dir())
        self.assertEqual(before,{name:(self.root/name).read_bytes() for name in FILES})

    def fixture(self):
        source=self.base/'source'
        for name in PACKAGE_FILES+('update/program.sha256',):
            (source/name).parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(PROJECT/name,source/name)
        return source

    def test_checksum_failure_changes_no_program_files(self):
        source=self.fixture()
        (source/FILES[0]).write_text('corrupted download')
        before={name:(self.root/name).read_bytes() for name in FILES}
        self.assertIn('Checksum verification failed',self.update(False,{'UPDATE_SOURCE_DIR':str(source)}).stderr)
        self.assertEqual(before,{name:(self.root/name).read_bytes() for name in FILES})

    def test_arbitrary_manifest_path_rejected(self):
        source=self.fixture()
        (source/'update/program.sha256').write_text('0'*64+'  ../../config/inputs/unwanted.map\n')
        self.assertIn('Unexpected file',self.update(False,{'UPDATE_SOURCE_DIR':str(source)}).stderr)

    def test_write_failure_restores_all_programs_and_missing_helper(self):
        (self.root/FILES[1]).unlink()
        before={name:(self.root/name).read_bytes() for name in FILES[:1]}
        bindir=self.base/'bin';bindir.mkdir()
        real_mv=shutil.which('mv')
        fake=bindir/'mv'
        fake.write_text('''#!/bin/bash
count=0
[ ! -f "$FAIL_COUNTER" ] || count=$(cat "$FAIL_COUNTER")
count=$((count+1))
printf '%s' "$count" > "$FAIL_COUNTER"
[ "$count" != 2 ] || exit 1
exec "REAL_MV" "$@"
'''.replace('REAL_MV',real_mv))
        fake.chmod(0o755)
        result=self.update(False,{'PATH':str(bindir)+':'+os.environ['PATH'],
                                  'FAIL_COUNTER':str(self.base/'count')})
        self.assertIn('Restoring previous program',result.stderr)
        self.assertEqual(before,{name:(self.root/name).read_bytes() for name in FILES[:1]})
        self.assertFalse((self.root/FILES[1]).exists())

    def test_v031_updater_can_migrate_through_compatibility_bridge(self):
        old=(PROJECT/'tests/fixtures/updater-v0.3.1.sh').read_bytes()
        legacy=self.root/LEGACY
        legacy.write_bytes(old)
        first=subprocess.run(['bash',str(legacy),'--no-pause'],env=self.env,capture_output=True,text=True)
        self.assertEqual(first.returncode,0,first.stdout+first.stderr)
        self.assertTrue(legacy.exists())
        self.assertEqual(legacy.read_bytes(),(PROJECT/LEGACY).read_bytes())
        second=subprocess.run(['bash',str(legacy),'--no-pause'],env=self.env,capture_output=True,text=True)
        self.assertEqual(second.returncode,0,second.stdout+second.stderr)
        self.assertFalse(legacy.exists())
        for name,data in self.snapshot.items(): self.assertEqual((self.root/name).read_bytes(),data)

    def test_legacy_updater_is_backed_up_and_removed(self):
        legacy=self.root/LEGACY
        legacy.write_text('#!/bin/bash\nprintf "legacy updater\n"\n')
        self.update()
        self.assertFalse(legacy.exists())
        backups=list((self.root/'config/8bitdo-profiles').glob('program-backup-*'))
        self.assertEqual((backups[0]/LEGACY).read_text(),'#!/bin/bash\nprintf "legacy updater\n"\n')

    def network(self, fail=False):
        bindir=self.base/'network';bindir.mkdir()
        fake=bindir/'curl'
        fake.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
args=sys.argv[1:]; url=args[-3]; dest=pathlib.Path(args[-1])
with open(os.environ['URL_LOG'],'a') as log: log.write(url+'\\n')
sha='a'*40
if url.startswith('https://api.github.com/'):
    dest.write_text(json.dumps({'object':{'sha':sha}}));sys.exit(0)
prefix='https://raw.githubusercontent.com/Soopahfly/MisterFPGA-8BitDo-Selector/'+sha+'/'
assert url.startswith(prefix),url
name=url[len(prefix):]
if os.environ.get('FAKE_FAIL')=='1' and name.endswith('controller-menu'): sys.exit(22)
dest.write_bytes((pathlib.Path(os.environ['FAKE_SOURCE'])/name).read_bytes())
''')
        fake.chmod(0o755)
        return {'PATH':str(bindir)+':'+os.environ['PATH'],'UPDATE_SOURCE_DIR':'',
                'FAKE_SOURCE':str(PROJECT),'URL_LOG':str(self.base/'urls'),'FAKE_FAIL':'1' if fail else '0'}

    def test_online_update_pins_every_download_to_same_commit(self):
        self.update(env=self.network())
        urls=(self.base/'urls').read_text().splitlines()
        self.assertEqual(len(urls),5)
        self.assertTrue(all('/'+'a'*40+'/' in url for url in urls[1:]))
        self.assertEqual((self.root/FILES[0]).read_bytes(),(PROJECT/FILES[0]).read_bytes())

    def test_download_failure_leaves_program_files_unchanged(self):
        before={name:(self.root/name).read_bytes() for name in FILES}
        self.assertIn('Download failed',self.update(False,self.network(True)).stderr)
        self.assertEqual(before,{name:(self.root/name).read_bytes() for name in FILES})

if __name__=='__main__': unittest.main()
