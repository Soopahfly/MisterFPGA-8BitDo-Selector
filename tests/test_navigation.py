"""Native evdev translation, terminal controls and real selector integration.
The shipped ARM helper still needs testing on a MiSTer with physical pads.
"""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import termios
import time
import unittest

PROJECT = Path(__file__).resolve().parents[1]


class NavigationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.temp.name) / 'controller-menu'
        subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                        str(PROJECT / 'src/controller-menu.c'), '-o', str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def start(self, args, env=None, output_pipe=True):
        master, slave = pty.openpty()
        initial = termios.tcgetattr(slave)
        def session():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(args, stdin=slave,
                                   stdout=subprocess.PIPE if output_pipe else slave,
                                   stderr=slave, env=env, preexec_fn=session)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        return process, master, slave, initial

    def screen(self, master, phrase):
        data = b''
        deadline = time.monotonic() + 5
        while phrase not in data and time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                data += os.read(master, 65536)
        self.assertIn(phrase, data)
        return data

    def test_arrow_enter_and_terminal_restoration(self):
        p, master, slave, initial = self.start([str(self.binary), 'Test', 'Navigation',
                                             'first|First', 'second|Second', 'exit|Exit'])
        self.screen(master, b'Start: select')
        os.write(master, b'\x1b[B\r')
        output, _ = p.communicate(timeout=5)
        self.assertEqual(output, b'second\n')
        self.assertEqual(p.returncode, 0)
        self.assertEqual(termios.tcgetattr(slave), initial)

    def test_escape_and_signal_cancel_restore_terminal(self):
        for key in (b'\x1b', None):
            p, master, slave, initial = self.start([str(self.binary), 'Test', '', 'exit|Exit'])
            self.screen(master, b'Start: select')
            if key: os.write(master, key)
            else: p.send_signal(signal.SIGTERM)
            output, _ = p.communicate(timeout=5)
            self.assertEqual(output, b'cancel\n' if key else b'')
            self.assertEqual(p.returncode, 0 if key else 143)
            self.assertEqual(termios.tcgetattr(slave), initial)

    def test_real_selector_applies_profile_and_finishes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            env = os.environ | {'MISTER_ROOT': str(root)}
            subprocess.run(['bash', str(PROJECT / 'install.sh')], env=env,
                           capture_output=True, check=True)
            env |= {'NAV_HELPER': str(self.binary), 'CONFIG_ROOT': str(root / 'config'),
                    'RECEIVER_MODE': 'xinput', 'INPUT_DEVICES': '/dev/null'}
            p, master, _, _ = self.start(['bash', str(PROJECT / 'Scripts/8BitDo_Controller_Selector.sh')],
                                        env=env, output_pipe=False)
            self.screen(master, b'Start: select')
            os.write(master, b'\x1b[B\x1b[B\r')
            self.screen(master, b'to finish.')
            os.write(master, b'\r')
            p.wait(timeout=5)
            self.assertEqual(p.returncode, 0)
            self.assertEqual((root / 'config/8bitdo-profiles/xinput/last-selected').read_text().strip(), 'xbox')
            name = 'N64_input_2dc8_3106_v3.map'
            self.assertEqual((root / 'config/inputs' / name).read_bytes(),
                             (root / 'config/8bitdo-profiles/xinput/xbox' / name).read_bytes())

    def test_capture_cancel_leaves_profiles_and_active_maps_alone(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            subprocess.run(['bash', str(PROJECT / 'install.sh')],
                           env=os.environ | {'MISTER_ROOT': str(root)}, capture_output=True, check=True)
            env=os.environ | {'NAV_HELPER': str(self.binary), 'CONFIG_ROOT': str(root / 'config'),
                              'RECEIVER_MODE': 'xinput', 'INPUT_DEVICES': '/dev/null'}
            before={str(p.relative_to(root)):p.read_bytes() for p in root.rglob('*.map')}
            p,master,_,_=self.start(['bash', str(PROJECT / 'Scripts/8BitDo_Controller_Selector.sh')], env,False)
            self.screen(master,b'Start: select')
            os.write(master,b'\x1b[B'*4+b'\r')
            self.screen(master,b'Which paired controller')
            os.write(master,b'\r')  # Cancel is the default, never an implicit save.
            p.wait(timeout=5)
            self.assertEqual(p.returncode,0)
            self.assertEqual(before,{str(p.relative_to(root)):p.read_bytes() for p in root.rglob('*.map')})

    def test_offline_mode_menu_can_update_without_choosing_receiver_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            subprocess.run(['bash',str(PROJECT/'install.sh')],
                           env=os.environ|{'MISTER_ROOT':str(root)},capture_output=True,check=True)
            env=os.environ|{'MISTER_ROOT':str(root),'CONFIG_ROOT':str(root/'config'),
                            'NAV_HELPER':str(self.binary),'RECEIVER_MODE':'auto',
                            'INPUT_DEVICES':'/dev/null','UPDATE_SOURCE_DIR':str(PROJECT)}
            p,master,_,_=self.start(['bash',str(PROJECT/'Scripts/8BitDo_Controller_Selector.sh')],env,False)
            self.screen(master,b'Choose receiver USB mode')
            os.write(master,b'\x1b[B\x1b[B\r')
            self.screen(master,b'Press Enter to finish:')
            os.write(master,b'\r')
            p.wait(timeout=5)
            self.assertEqual(p.returncode,0)
            self.assertFalse((root/'config/8bitdo-profiles/last-selected').exists())
            self.assertFalse((root/'Scripts/8BitDo_Selector_Update.sh').exists())

    def test_evdev_actions_and_held_buttons(self):
        source=Path(self.temp.name)/'events.c'
        source.write_text(r'''
#define main helper_main
#include "SOURCE"
#undef main
#include <assert.h>
int main(void) {
    struct pad p={.fd=-1};
    struct evdev_event e={.type=EV_KEY,.code=BTN_START,.value=1};
    assert(action(&p,&e)==2);
    assert(action(&p,&e)==0);
    e.value=2; assert(action(&p,&e)==0);
    e.value=0; assert(action(&p,&e)==0);
    e.value=1; assert(action(&p,&e)==2);
    e.code=BTN_SOUTH; assert(action(&p,&e)==0);
    e.code=BTN_EAST; assert(action(&p,&e)==0);
    e.type=EV_ABS; e.code=ABS_HAT0Y; e.value=-1;
    assert(action(&p,&e)==-1); assert(action(&p,&e)==0);
    e.value=0; assert(action(&p,&e)==0);
    e.value=1; assert(action(&p,&e)==1);
    e.type=EV_KEY; e.code=BTN_DPAD_UP; e.value=1;
    assert(action(&p,&e)==-1); assert(action(&p,&e)==0);
    e.type=EV_SYN; e.code=SYN_DROPPED; assert(action(&p,&e)==0);
    e.type=EV_KEY; e.code=BTN_START; assert(action(&p,&e)==0);
    e.type=EV_SYN; e.code=SYN_REPORT; assert(action(&p,&e)==0); assert(!p.dropped);
    return 0;
}
'''.replace('SOURCE',str(PROJECT / 'src/controller-menu.c')))
        runner=Path(self.temp.name)/'events'
        subprocess.run(['gcc','-std=c11','-Wall','-Wextra','-Werror',str(source),'-o',str(runner)],check=True)
        subprocess.run([str(runner)],check=True)


if __name__ == '__main__':
    unittest.main()
