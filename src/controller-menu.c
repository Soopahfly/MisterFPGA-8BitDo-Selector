/* SPDX-License-Identifier: MIT
 * Raw evdev menu for MiSTer. No MiSTer mappings or runtime libraries required.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

/* evdev timestamps use kernel unsigned longs, even with musl's 64-bit time_t.
 * Using libc struct timeval here would mis-size records on 32-bit ARM. */
struct evdev_event { unsigned long seconds, microseconds; __u16 type, code; __s32 value; };
_Static_assert(sizeof(struct evdev_event)==2*sizeof(unsigned long)+8, "evdev ABI");
#define MAX_PADS 16
#define MAX_ITEMS 16
#define BITS (sizeof(unsigned long)*8)
#define HAS(a,n) (((a)[(n)/BITS] >> ((n)%BITS)) & 1UL)
struct pad { int fd, hat, start, up, down, dropped; char path[128]; };
static struct pad pads[MAX_PADS];
static volatile sig_atomic_t stopped;
static struct termios original;
static int tty = -1, raw;
static void stop(int sig) { stopped = sig; }
static void cleanup(void) {
    for (int i=0;i<MAX_PADS;i++) if (pads[i].fd >= 0) close(pads[i].fd);
    if (raw) tcsetattr(tty,TCSANOW,&original);
    if (tty >= 0) { dprintf(tty,"\033[?25h\033[0m\n"); close(tty); }
}
static void resync(struct pad *p) {
    unsigned long keys[(KEY_MAX/BITS)+1] = {0};
    struct input_absinfo abs;
    p->hat=0; p->start=p->up=p->down=0;
    if (ioctl(p->fd, EVIOCGABS(ABS_HAT0Y), &abs)>=0) p->hat=abs.value;
    if (ioctl(p->fd, EVIOCGKEY(sizeof(keys)),keys)>=0) {
        p->start=HAS(keys,BTN_START); p->up=HAS(keys,BTN_DPAD_UP); p->down=HAS(keys,BTN_DPAD_DOWN);
    }
}
/* -1 up, 1 down, 2 confirm. Held buttons must release before next dialog. */
static int action(struct pad *p, const struct evdev_event *e) {
    if (e->type==EV_SYN && e->code==SYN_DROPPED) { p->dropped=1; return 0; }
    if (p->dropped) {
        if (e->type==EV_SYN && e->code==SYN_REPORT) { resync(p); p->dropped=0; }
        return 0;
    }
    if (e->type==EV_ABS && e->code==ABS_HAT0Y) {
        int old=p->hat; p->hat=e->value;
        return e->value != old ? (e->value<0 ? -1 : e->value>0 ? 1 : 0) : 0;
    }
    if (e->type==EV_KEY && e->value!=2) {
        int *state=NULL, result=0;
        if (e->code==BTN_START) {state=&p->start; result=2;}
        if (e->code==BTN_DPAD_UP) {state=&p->up; result=-1;}
        if (e->code==BTN_DPAD_DOWN) {state=&p->down; result=1;}
        if (state) { int old=*state; *state=e->value; return e->value==1 && !old ? result : 0; }
    }
    return 0;
}
static int scan(void) {
    int added=0;
    glob_t paths={0};
    if (glob("/dev/input/event*",0,NULL,&paths)!=0) { globfree(&paths); return 0; }
    for(size_t j=0;j<paths.gl_pathc;j++) {
        int slot=-1, known=0;
        for(int i=0;i<MAX_PADS;i++) {
            if(pads[i].fd<0) slot=i;
            else if(!strcmp(pads[i].path,paths.gl_pathv[j])) known=1;
        }
        if(known || slot<0) continue;
        int fd=open(paths.gl_pathv[j],O_RDONLY|O_NONBLOCK|O_CLOEXEC);
        if(fd<0) continue;
        struct input_id id;
        unsigned long keys[(KEY_MAX/BITS)+1]={0}, axes[(ABS_MAX/BITS)+1]={0};
        if(ioctl(fd,EVIOCGID,&id)<0 ||
           !((id.vendor==0x2dc8 && id.product==0x3106) || (id.vendor==0x057e && id.product==0x2009)) ||
           ioctl(fd,EVIOCGBIT(EV_KEY,sizeof(keys)),keys)<0 ||
           ioctl(fd,EVIOCGBIT(EV_ABS,sizeof(axes)),axes)<0 || !HAS(keys,BTN_START) ||
           !(HAS(axes,ABS_HAT0Y) || (HAS(keys,BTN_DPAD_UP) && HAS(keys,BTN_DPAD_DOWN))) ||
           ioctl(fd,EVIOCGRAB,1)<0) { close(fd); continue; }
        pads[slot].fd=fd; pads[slot].dropped=0;
        snprintf(pads[slot].path,sizeof(pads[slot].path),"%s",paths.gl_pathv[j]);
        resync(&pads[slot]); added++;
    }
    globfree(&paths);
    return added;
}
static void draw(const char *title, const char *subtitle, char **items, int n, int selected, int wait) {
    if(wait) { dprintf(tty,"\n%s\n%s\nPress Start, or Enter, to finish.\n",title,subtitle); return; }
    dprintf(tty,"\033[2J\033[H\033[?25l%s\n%s\n\n",title,subtitle);
    for(int i=0;i<n;i++) {
        const char *label=strchr(items[i],'|')+1;
        dprintf(tty,"%s %s%s\n",i==selected?"\033[7m >":"   ",label,i==selected?" \033[0m":"");
    }
    int connected=0;
    for(int i=0;i<MAX_PADS;i++) connected+=pads[i].fd>=0;
    dprintf(tty,"\nD-pad: move   Start: select\nKeyboard: arrows / Enter   Esc: cancel\n%s\n",
            connected?"Receiver gamepad connected":"No available receiver gamepad. Pair a pad, or use the keyboard.");
}
int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"--check")) return 0;
    int wait=argc>1 && !strcmp(argv[1],"--wait");
    if(wait) { argc--; argv++; }
    int n=argc-3;
    if(n<1 || n>MAX_ITEMS) return 2;
    for(int i=3;i<argc;i++) {
        char *sep=strchr(argv[i],'|');
        if(!sep || sep==argv[i] || sep-argv[i]>32 || !sep[1]) return 2;
    }
    for(int i=0;i<MAX_PADS;i++) pads[i].fd=-1;
    tty=open("/dev/tty",O_RDWR|O_CLOEXEC);
    if(tty<0 || tcgetattr(tty,&original)<0) return 2;
    atexit(cleanup);
    struct termios t=original; cfmakeraw(&t); t.c_lflag|=ISIG; t.c_oflag|=OPOST|ONLCR;
    if(tcsetattr(tty,TCSANOW,&t)<0) return 2;
    raw=1;
    signal(SIGINT,stop); signal(SIGTERM,stop); signal(SIGHUP,stop);
    scan();
    int selected=0, dirty=1, escape=0;
    struct timespec last={0}, escape_at={0};
    while(!stopped) {
        struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
        if(now.tv_sec!=last.tv_sec) { if(scan() && !wait) dirty=1; last=now; }
        if(dirty) {draw(argv[1],argv[2],argv+3,n,selected,wait); dirty=0;}
        struct pollfd fds[MAX_PADS+1];
        fds[0]=(struct pollfd){tty,POLLIN,0};
        for(int i=0;i<MAX_PADS;i++) fds[i+1]=(struct pollfd){pads[i].fd,POLLIN,0};
        if(poll(fds,MAX_PADS+1,50)<0 && errno!=EINTR) return 2;
        int move=0, confirm=0;
        if(fds[0].revents&POLLIN) {
            unsigned char bytes[64]; ssize_t count=read(tty,bytes,sizeof(bytes));
            if(count==0) return 2;
            for(ssize_t i=0;i<count;i++) {
                unsigned char c=bytes[i];
                if(escape==1 && (c=='[' || c=='O')) {escape=2;continue;}
                if(escape==2) { if(c=='A') move--; if(c=='B') move++; escape=0;continue; }
                if(escape==1) {printf("cancel\n");return 0;}
                if(c==27) {escape=1;escape_at=now;}
                else if(c=='\r' || c=='\n') confirm=1;
                else if(c=='k') move--;
                else if(c=='j') move++;
            }
        }
        if(escape && (now.tv_sec-escape_at.tv_sec)*1000+(now.tv_nsec-escape_at.tv_nsec)/1000000>150) {
            printf("cancel\n");return 0;
        }
        for(int i=0;i<MAX_PADS;i++) {
            if(pads[i].fd<0) continue;
            if(fds[i+1].revents&(POLLHUP|POLLERR|POLLNVAL)) {close(pads[i].fd);pads[i].fd=-1;dirty=!wait;continue;}
            if(fds[i+1].revents&POLLIN) {
                struct evdev_event e[32]; ssize_t len;
                while((len=read(pads[i].fd,e,sizeof(e)))>0) {
                    for(size_t j=0;j<(size_t)len/sizeof(*e);j++) {
                        int a=action(&pads[i],&e[j]); if(a==2) confirm=1; else if(a) move+=a;
                    }
                }
                if(len<0 && errno!=EAGAIN && errno!=EINTR) {close(pads[i].fd);pads[i].fd=-1;dirty=!wait;}
            }
        }
        if(move && !wait) {selected=(selected+move%n+n)%n;dirty=1;}
        if(confirm) {char *sep=strchr(argv[selected+3],'|');printf("%.*s\n",(int)(sep-argv[selected+3]),argv[selected+3]);return 0;}
    }
    return 128+stopped;
}
