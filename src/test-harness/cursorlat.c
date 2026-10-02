/*
 * cursorlat - measure how long the X cursor takes to move on screen.
 *
 * Creates a virtual mouse with uinput, prints its /dev/input/eventN path,
 * waits for a line on stdin (start X with "-mouse <path>" in between), then
 * repeatedly moves the pointer a few pixels and times how long it takes for
 * the framebuffer to change. Prints "LAT <ms>" per trial and a summary.
 *
 * usage: cursorlat [trials]   (trials 0: stream test - 60 moves of 2 px at
 *        16 ms, like a real ADB mouse, then time until the screen settles)
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static int ufd;

static double now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static void emit(int type, int code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.code = code;
	ev.value = value;
	if (write(ufd, &ev, sizeof(ev)) != sizeof(ev))
		perror("uinput write");
}

static void move(int dx, int dy)
{
	emit(EV_REL, REL_X, dx);
	emit(EV_REL, REL_Y, dy);
	emit(EV_SYN, SYN_REPORT, 0);
}

/* Find the event node the kernel gave our virtual device. */
static void print_event_path(void)
{
	char sys[64], name[256];

	if (ioctl(ufd, UI_GET_SYSNAME(sizeof(sys)), sys) >= 0) {
		DIR *d;
		struct dirent *e;

		snprintf(name, sizeof(name), "/sys/devices/virtual/input/%s", sys);
		d = opendir(name);
		while (d && (e = readdir(d)))
			if (!strncmp(e->d_name, "event", 5)) {
				printf("/dev/input/%s\n", e->d_name);
				break;
			}
		if (d)
			closedir(d);
	}
	fflush(stdout);
}

static int cmpd(const void *a, const void *b)
{
	double x = *(const double *)a, y = *(const double *)b;

	return x < y ? -1 : x > y;
}

int main(int argc, char **argv)
{
	struct uinput_setup us;
	struct fb_fix_screeninfo fix;
	struct fb_var_screeninfo var;
	unsigned char *fb, *before;
	int trials = argc > 1 ? atoi(argv[1]) : 20;
	int fbfd, i, n = 0, timeouts = 0;
	double lat[256], sum = 0;
	char line[16];

	ufd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (ufd < 0) {
		perror("/dev/uinput");
		return 1;
	}
	ioctl(ufd, UI_SET_EVBIT, EV_KEY);
	ioctl(ufd, UI_SET_KEYBIT, BTN_LEFT);
	ioctl(ufd, UI_SET_EVBIT, EV_REL);
	ioctl(ufd, UI_SET_RELBIT, REL_X);
	ioctl(ufd, UI_SET_RELBIT, REL_Y);
	memset(&us, 0, sizeof(us));
	us.id.bustype = BUS_VIRTUAL;
	strcpy(us.name, "cursorlat mouse");
	ioctl(ufd, UI_DEV_SETUP, &us);
	ioctl(ufd, UI_DEV_CREATE);
	usleep(200000);
	print_event_path();

	/* wait until X is running with our device */
	if (!fgets(line, sizeof(line), stdin))
		return 1;

	fbfd = open("/dev/fb0", O_RDONLY);
	if (fbfd < 0 || ioctl(fbfd, FBIOGET_FSCREENINFO, &fix) < 0 ||
	    ioctl(fbfd, FBIOGET_VSCREENINFO, &var) < 0) {
		perror("/dev/fb0");
		return 1;
	}
	fb = mmap(NULL, fix.smem_len, PROT_READ, MAP_SHARED, fbfd, 0);
	before = malloc(fix.smem_len);

	/* park the pointer near the middle, away from window borders */
	move(-2000, -2000);
	usleep(500000);
	move(150, 150);
	sleep(2);

	if (trials == 0) {
		/* stream: one second of steady motion, then wait for the cursor to
		   catch up (screen unchanged for 200 ms) */
		double tlast, tchange;
		int round;

		for (round = 0; round < 5; round++) {
			int d = (round & 1) ? -2 : 2;

			for (i = 0; i < 60; i++) {
				move(d, d);
				usleep(16000);
			}
			tlast = tchange = now_ms();
			memcpy(before, fb, fix.smem_len);
			while (now_ms() - tchange < 200 && now_ms() - tlast < 20000) {
				usleep(5000);
				if (memcmp(before, fb, fix.smem_len)) {
					memcpy(before, fb, fix.smem_len);
					tchange = now_ms();
				}
			}
			lat[n] = tchange - tlast;
			sum += lat[n++];
			printf("DRAIN %.1f\n", tchange - tlast);
			fflush(stdout);
			sleep(1);
		}
		qsort(lat, n, sizeof(lat[0]), cmpd);
		printf("SUMMARY n=%d mean=%.1fms median=%.1fms p90=%.1fms max=%.1fms timeouts=0\n",
		       n, sum / n, lat[n / 2], lat[(n * 9) / 10], lat[n - 1]);
		ioctl(ufd, UI_DEV_DESTROY);
		return 0;
	}
	if (trials > 256)
		trials = 256;
	for (i = 0; i < trials; i++) {
		double t0, t;
		int d = (i & 1) ? -3 : 3;	/* small steps: no acceleration */

		memcpy(before, fb, fix.smem_len);
		t0 = now_ms();
		move(d, d);
		for (;;) {
			t = now_ms();
			if (memcmp(before, fb, fix.smem_len))
				break;
			if (t - t0 > 5000) {
				timeouts++;
				break;
			}
			usleep(2000);
		}
		if (t - t0 <= 5000) {
			lat[n++] = t - t0;
			sum += t - t0;
			printf("LAT %.1f\n", t - t0);
		} else {
			printf("LAT timeout\n");
		}
		fflush(stdout);
		usleep(300000);	/* let things settle between trials */
	}
	if (n) {
		qsort(lat, n, sizeof(lat[0]), cmpd);
		printf("SUMMARY n=%d mean=%.1fms median=%.1fms p90=%.1fms max=%.1fms timeouts=%d\n",
		       n, sum / n, lat[n / 2], lat[(n * 9) / 10], lat[n - 1], timeouts);
	}
	ioctl(ufd, UI_DEV_DESTROY);
	return 0;
}
