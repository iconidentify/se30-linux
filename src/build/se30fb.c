/*
 * se30fb - show an Xvfb screen on the Mac's framebuffer and feed it input.
 *
 * Xorg's fbdev driver can't drive a 1 bit-per-pixel display and Xvfb can't
 * run at depth 1, so X runs as an 8-bit StaticGray Xvfb rendering into a
 * memory-mapped XWD file (-fbdir). This program watches the DAMAGE
 * extension, converts changed areas to 1 bpp with a 4x4 ordered dither and
 * writes them to /dev/fb0. It also forwards the ADB keyboard and mouse
 * (evdev) into X through XTEST.
 *
 * The pointer is drawn here, straight onto the framebuffer, as soon as the
 * mouse moves; X's own cursor is hidden (XFixes) so moving it never waits
 * for the X server. Key repeat comes from the kernel, so a busy X server
 * can't turn one keystroke into several.
 *
 * The Mac's mouse has one button: Option-click sends button 2 (paste in
 * xterm), Command-click sends button 3.
 *
 * usage: se30fb /run/xvfb/Xvfb_screen0      (with DISPLAY set)
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <X11/XWDFile.h>
#include <X11/Xlib.h>
#include <X11/extensions/Xdamage.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/XTest.h>

#define MAX_INPUTS 8
#define CURSOR_MAX 32

static int tty_fd = -1;
static int input_fds[MAX_INPUTS];
static int ninputs;

static unsigned char *src, *fb;
static int src_stride, src_bpp, fb_stride, scr_w, scr_h;
static unsigned char threshold[4][8];

/* Our pointer: hotspot position and a 1 bpp image (mask + black bits) */
static int ptr_x, ptr_y;
static int cur_w, cur_h, cur_xhot, cur_yhot;
static unsigned char cur_mask[CURSOR_MAX][CURSOR_MAX];
static unsigned char cur_black[CURSOR_MAX][CURSOR_MAX];
static int cur_shown, cur_rx, cur_ry;	/* where it was last drawn */

static void restore_console(void)
{
	int i;

	if (tty_fd >= 0)
		ioctl(tty_fd, KDSETMODE, KD_TEXT);
	for (i = 0; i < ninputs; i++)
		ioctl(input_fds[i], EVIOCGRAB, 0);
}

static void on_signal(int sig)
{
	restore_console();
	_exit(128 + sig);
}

static int on_xio_error(Display *dpy)
{
	(void)dpy;
	restore_console();
	exit(0);
}

/* Copy a rectangle of the X screen to the framebuffer. */
static void update(int x, int y, int w, int h)
{
	int x0, x1, y1, row, bx;

	if (x < 0) { w += x; x = 0; }
	if (y < 0) { h += y; y = 0; }
	if (x + w > scr_w) w = scr_w - x;
	if (y + h > scr_h) h = scr_h - y;
	if (w <= 0 || h <= 0)
		return;
	y1 = y + h;
	x0 = x / 8;
	x1 = (x + w + 7) / 8;

	if (src_bpp == 1) {
		for (row = y; row < y1; row++)
			memcpy(fb + row * fb_stride + x0, src + row * src_stride + x0, x1 - x0);
		return;
	}

	/* 8-bit gray to 1 bpp, Mac convention: set bit = black */
	for (row = y; row < y1; row++) {
		const unsigned char *s = src + row * src_stride + x0 * 8;
		const unsigned char *t = threshold[row & 3];
		unsigned char *d = fb + row * fb_stride + x0;

		for (bx = x0; bx < x1; bx++, s += 8)
			*d++ = (s[0] < t[0]) << 7 | (s[1] < t[1]) << 6 |
			       (s[2] < t[2]) << 5 | (s[3] < t[3]) << 4 |
			       (s[4] < t[4]) << 3 | (s[5] < t[5]) << 2 |
			       (s[6] < t[6]) << 1 | (s[7] < t[7]);
	}
}

static void hide_cursor(void)
{
	if (cur_shown)
		update(cur_rx, cur_ry, cur_w, cur_h);
	cur_shown = 0;
}

static void draw_cursor(void)
{
	int r, c;

	cur_rx = ptr_x - cur_xhot;
	cur_ry = ptr_y - cur_yhot;
	for (r = 0; r < cur_h; r++) {
		int y = cur_ry + r;

		if (y < 0 || y >= scr_h)
			continue;
		for (c = 0; c < cur_w; c++) {
			int x = cur_rx + c;
			unsigned char *d, bit;

			if (x < 0 || x >= scr_w || !cur_mask[r][c])
				continue;
			d = fb + y * fb_stride + x / 8;
			bit = 0x80 >> (x & 7);
			if (cur_black[r][c])
				*d |= bit;
			else
				*d &= ~bit;
		}
	}
	cur_shown = 1;
}

/* Take X's current cursor image (ARGB) and reduce it to 1 bpp. */
static void load_cursor(Display *dpy)
{
	XFixesCursorImage *img = XFixesGetCursorImage(dpy);
	int r, c;

	if (!img)
		return;
	hide_cursor();
	cur_w = img->width < CURSOR_MAX ? img->width : CURSOR_MAX;
	cur_h = img->height < CURSOR_MAX ? img->height : CURSOR_MAX;
	cur_xhot = img->xhot;
	cur_yhot = img->yhot;
	for (r = 0; r < cur_h; r++) {
		for (c = 0; c < cur_w; c++) {
			unsigned long p = img->pixels[r * img->width + c];
			unsigned int a = (p >> 24) & 0xff;
			unsigned int g = ((p >> 16 & 0xff) + (p >> 8 & 0xff) + (p & 0xff)) / 3;

			cur_mask[r][c] = a >= 128;
			cur_black[r][c] = g < 128;
		}
	}
	XFree(img);
	draw_cursor();
}

static int test_bit(const unsigned long *bits, int n)
{
	return (bits[n / (8 * sizeof(long))] >> (n % (8 * sizeof(long)))) & 1;
}

/* Grab every evdev device that is a keyboard or a relative pointer. */
static void open_inputs(void)
{
	char path[32];
	int i;

	for (i = 0; i < 16 && ninputs < MAX_INPUTS; i++) {
		unsigned long evbits[1] = {0};
		unsigned long keybits[KEY_MAX / (8 * sizeof(long)) + 1] = {0};
		int fd;

		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits);
		ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits);
		if (test_bit(evbits, EV_REL) ||
		    (test_bit(evbits, EV_KEY) && test_bit(keybits, KEY_A))) {
			if (test_bit(evbits, EV_REP)) {
				/* slower kernel repeat: 500 ms delay, 10 per second */
				unsigned int rep[2] = {500, 100};

				ioctl(fd, EVIOCSREP, rep);
			}
			ioctl(fd, EVIOCGRAB, 1);
			input_fds[ninputs++] = fd;
		} else {
			close(fd);
		}
	}
}

/* The ADB mouse reports small raw counts; speed up larger movements. */
static int accel(int d)
{
	int a = d < 0 ? -d : d;

	return a >= 4 ? d * 2 : d;
}

int main(int argc, char **argv)
{
	static const unsigned char bayer[4][4] = {
		{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5},
	};
	struct fb_fix_screeninfo fix;
	struct fb_var_screeninfo var;
	XWDFileHeader *hdr;
	unsigned char *xwd;
	Display *dpy;
	Window root;
	Damage damage;
	XserverRegion region;
	struct stat st;
	int xfd, fbfd, i, dmg_ev, dmg_err, fx_ev, fx_err;
	int mod_option = 0, mod_command = 0, held_button = 0;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /run/xvfb/Xvfb_screen0\n", argv[0]);
		return 2;
	}

	xfd = open(argv[1], O_RDONLY);
	if (xfd < 0 || fstat(xfd, &st) < 0) {
		perror(argv[1]);
		return 1;
	}
	xwd = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED, xfd, 0);
	if (xwd == MAP_FAILED) {
		perror("mmap xwd");
		return 1;
	}
	hdr = (XWDFileHeader *)xwd;
	src = xwd + hdr->header_size + hdr->ncolors * sz_XWDColor;
	src_stride = hdr->bytes_per_line;
	src_bpp = hdr->bits_per_pixel;

	fbfd = open("/dev/fb0", O_RDWR);
	if (fbfd < 0 || ioctl(fbfd, FBIOGET_FSCREENINFO, &fix) < 0 ||
	    ioctl(fbfd, FBIOGET_VSCREENINFO, &var) < 0) {
		perror("/dev/fb0");
		return 1;
	}
	fb = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fbfd, 0);
	if (fb == MAP_FAILED) {
		perror("mmap fb");
		return 1;
	}
	if (var.bits_per_pixel != 1 || (src_bpp != 1 && src_bpp != 8)) {
		fprintf(stderr, "se30fb: needs a 1 bpp framebuffer and a 1 or 8 bpp X screen (got %u and %d)\n",
			var.bits_per_pixel, src_bpp);
		return 1;
	}
	fb_stride = fix.line_length;
	scr_w = var.xres < hdr->pixmap_width ? var.xres : (int)hdr->pixmap_width;
	scr_h = var.yres < hdr->pixmap_height ? var.yres : (int)hdr->pixmap_height;
	for (i = 0; i < 32; i++)
		threshold[i / 8][i % 8] = bayer[i / 8][i % 4] * 16 + 8;

	dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "se30fb: can't open display\n");
		return 1;
	}
	XSetIOErrorHandler(on_xio_error);
	if (!XDamageQueryExtension(dpy, &dmg_ev, &dmg_err) ||
	    !XFixesQueryExtension(dpy, &fx_ev, &fx_err)) {
		fprintf(stderr, "se30fb: X server lacks DAMAGE or XFIXES\n");
		return 1;
	}
	{
		int major = 1, minor = 1;

		XDamageQueryVersion(dpy, &major, &minor);
		major = 4; minor = 0;
		XFixesQueryVersion(dpy, &major, &minor);
	}
	root = DefaultRootWindow(dpy);
	damage = XDamageCreate(dpy, root, XDamageReportNonEmpty);
	region = XFixesCreateRegion(dpy, NULL, 0);
	XFixesSelectCursorInput(dpy, root, XFixesDisplayCursorNotifyMask);
	XFixesHideCursor(dpy, root);
	XAutoRepeatOff(dpy);
	{
		Window rw, cw;
		int wx, wy;
		unsigned int mask;

		XQueryPointer(dpy, root, &rw, &cw, &ptr_x, &ptr_y, &wx, &wy, &mask);
	}

	tty_fd = open("/dev/tty0", O_RDWR);
	if (tty_fd >= 0)
		ioctl(tty_fd, KDSETMODE, KD_GRAPHICS);
	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);
	signal(SIGHUP, on_signal);
	open_inputs();

	update(0, 0, scr_w, scr_h);
	load_cursor(dpy);
	XFlush(dpy);

	for (;;) {
		struct pollfd pfd[MAX_INPUTS + 1];
		int dx = 0, dy = 0, moved = 0, n;

		/* Changed areas: fetching the region also waits for the drawing. */
		while (XPending(dpy)) {
			XEvent ev;

			XNextEvent(dpy, &ev);
			if (ev.type == dmg_ev + XDamageNotify) {
				XRectangle *r;
				int nr;

				XDamageSubtract(dpy, damage, None, region);
				r = XFixesFetchRegion(dpy, region, &nr);
				for (i = 0; i < nr; i++)
					update(r[i].x, r[i].y, r[i].width, r[i].height);
				if (r)
					XFree(r);
				if (nr && cur_shown)
					draw_cursor();
			} else if (ev.type == fx_ev + XFixesCursorNotify) {
				load_cursor(dpy);
			}
		}

		pfd[0].fd = ConnectionNumber(dpy);
		pfd[0].events = POLLIN;
		for (i = 0; i < ninputs; i++) {
			pfd[i + 1].fd = input_fds[i];
			pfd[i + 1].events = POLLIN;
		}
		n = poll(pfd, ninputs + 1, -1);
		if (n <= 0)
			continue;

		for (i = 0; i < ninputs; i++) {
			struct input_event ev;

			if (!(pfd[i + 1].revents & POLLIN))
				continue;
			while (read(input_fds[i], &ev, sizeof(ev)) == sizeof(ev)) {
				if (ev.type == EV_REL) {
					if (ev.code == REL_X)
						dx += accel(ev.value);
					else if (ev.code == REL_Y)
						dy += accel(ev.value);
				} else if (ev.type == EV_KEY && ev.code == BTN_LEFT) {
					if (ev.value == 1) {
						held_button = mod_option ? 2 : mod_command ? 3 : 1;
						XTestFakeButtonEvent(dpy, held_button, True, CurrentTime);
					} else if (ev.value == 0 && held_button) {
						XTestFakeButtonEvent(dpy, held_button, False, CurrentTime);
						held_button = 0;
					}
				} else if (ev.type == EV_KEY && (ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE)) {
					if (ev.value != 2)
						XTestFakeButtonEvent(dpy, ev.code == BTN_RIGHT ? 3 : 2,
								     ev.value, CurrentTime);
				} else if (ev.type == EV_KEY && ev.code < BTN_MISC) {
					/* evdev keycode + 8 = X keycode */
					unsigned int kc = ev.code + 8;

					if (ev.code == KEY_LEFTALT || ev.code == KEY_RIGHTALT)
						mod_option = ev.value != 0;
					if (ev.code == KEY_LEFTMETA || ev.code == KEY_RIGHTMETA)
						mod_command = ev.value != 0;
					if (ev.value == 2) {
						/* kernel repeat: send it as a fresh keystroke */
						XTestFakeKeyEvent(dpy, kc, False, CurrentTime);
						XTestFakeKeyEvent(dpy, kc, True, CurrentTime);
					} else {
						XTestFakeKeyEvent(dpy, kc, ev.value, CurrentTime);
					}
				}
			}
		}

		/* Move our pointer right away, then tell X where it is. */
		if (dx || dy) {
			int nx = ptr_x + dx, ny = ptr_y + dy;

			nx = nx < 0 ? 0 : nx >= scr_w ? scr_w - 1 : nx;
			ny = ny < 0 ? 0 : ny >= scr_h ? scr_h - 1 : ny;
			if (nx != ptr_x || ny != ptr_y) {
				hide_cursor();
				ptr_x = nx;
				ptr_y = ny;
				draw_cursor();
				moved = 1;
			}
		}
		if (moved)
			XTestFakeMotionEvent(dpy, DefaultScreen(dpy), ptr_x, ptr_y, CurrentTime);
		XFlush(dpy);
	}
}
