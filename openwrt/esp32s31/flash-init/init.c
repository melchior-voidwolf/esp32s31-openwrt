/* flash-init.c — minimal static init for the OpenWrt flash firmware.
 * Mounts the virtual filesystems, probes the shm_flash MTD block device,
 * mounts the squashfs rootfs on /rom + tmpfs writable overlay on /overlay,
 * combines them into a writable overlayfs on /new (with graceful fallback
 * to read-only squashfs if overlayfs is absent), and switch_roots into /sbin/init.
 * Build: riscv32-openwrt-linux-musl-gcc -static -O2 -mabi=ilp32f -march=rv32imafc_zicsr_zifencei_zba_zbb_zbs -o init init.c
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static int mfd(const char *path)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd >= 0) {
		dup2(fd, 1);
		dup2(fd, 2);
	}
	return fd;
}

static void say(const char *s) { write(1, s, strlen(s)); }

static void mount_fs(const char *src, const char *type, const char *dst,
		     unsigned long flags)
{
	mkdir(dst, 0755);
	if (mount(src, dst, type, flags, NULL) != 0)
		say("mount failed\n");
}

/* switch_root: move newroot, chroot, exec the real init */
static void switch_root(const char *newroot)
{
	if (chdir(newroot) != 0)
		return;
	mount(".", "/", NULL, MS_MOVE, NULL);
	chroot(".");
	chdir("/");
}

int main(void)
{
	char buf[512];
	char *argv[] = { "/sbin/init", NULL };
	char *envp[] = { "HOME=/", "TERM=linux", NULL };
	int fd, ret;

	mfd("/dev/console");
	say("\nflash-init: booting\n");

	mount_fs(NULL, "proc", "/proc", 0);
	mount_fs(NULL, "sysfs", "/sys", 0);
	mount_fs("devtmpfs", "devtmpfs", "/dev", 0);

	say("flash-init: waiting for mtdblock0 (probe window)\n");
	/* esp_shm + mtd registration lands a few seconds in; poll */
	for (int i = 0; i < 100; i++) {
		fd = open("/dev/mtdblock0", O_RDONLY);
		if (fd >= 0)
			break;
		usleep(200 * 1000);
	}
	if (fd < 0) {
		say("flash-init: /dev/mtdblock0 never appeared\n");
		say("flash-init: /proc/mtd follows:\n");
		int pfd = open("/proc/mtd", O_RDONLY);
		if (pfd >= 0) {
			while (read(pfd, buf, sizeof buf) > 0)
				write(1, buf, strlen(buf) > 512 ? 512 : strlen(buf));
			close(pfd);
		}
		reboot(RB_AUTOBOOT);
		return 1;
	}
	say("flash-init: mtdblock0 opened\n");

	ret = read(fd, buf, 512);
	printf("flash-init: first-sector read ret=%d errno-ish first bytes "
	       "%02x %02x %02x %02x\n",
	       ret, (unsigned char)buf[0], (unsigned char)buf[1],
	       (unsigned char)buf[2], (unsigned char)buf[3]);
	close(fd);

	mkdir("/rom", 0755);
	ret = mount("/dev/mtdblock0", "/rom", "squashfs", MS_RDONLY, NULL);
	if (ret != 0) {
		printf("flash-init: squashfs mount failed ret=%d errno=%d (%s)\n",
		       ret, errno, strerror(errno));
		say("flash-init: halted\n");
		while (1)
			pause();
	}

	mkdir("/new", 0755);
	mkdir("/overlay", 0755);
	if (mount("tmpfs", "/overlay", "tmpfs", MS_NOATIME, "size=1024k,mode=0755") == 0) {
		mkdir("/overlay/upper", 0755);
		mkdir("/overlay/work", 0755);
		if (mount("overlay", "/new", "overlay", MS_NOATIME,
			  "lowerdir=/rom,upperdir=/overlay/upper,workdir=/overlay/work") == 0) {
			mkdir("/new/rom", 0755);
			mount("/rom", "/new/rom", NULL, MS_MOVE, NULL);
			mkdir("/new/overlay", 0755);
			mount("/overlay", "/new/overlay", NULL, MS_MOVE, NULL);
			say("flash-init: writable overlayfs root mounted, switching\n");
		} else {
			umount("/overlay");
			mount("/rom", "/new", NULL, MS_MOVE, NULL);
			say("flash-init: ro squashfs root mounted (overlay fallback), switching\n");
		}
	} else {
		mount("/rom", "/new", NULL, MS_MOVE, NULL);
		say("flash-init: ro squashfs root mounted, switching\n");
	}

	/* keep the console: bind old /dev/console into the new root */
	mkdir("/new/dev", 0755);
	mount("/dev", "/new/dev", NULL, MS_MOVE, NULL);

	switch_root("/new");

	/* re-open console after chroot (dev was moved) */
	mfd("/dev/console");

	if (access("/sbin/init", X_OK) == 0) {
		execve("/sbin/init", argv, envp);
	}
	/* fallback: OpenWrt preinit needs a shell; without busybox we can't
	 * go further — report and park */
	say("flash-init: /sbin/init missing\n");
	while (1)
		pause();
	return 0;
}
