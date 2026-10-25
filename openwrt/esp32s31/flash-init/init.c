/* flash-init.c — minimal static init for the OpenWrt flash firmware.
 * Mount the virtual filesystems, probe the shm_flash MTD block device,
 * mount squashfs on /rom, then use a persistent UBIFS overlay when possible,
 * with tmpfs and read-only squashfs fallbacks.  No data is erased.
 * Build: riscv32-openwrt-linux-musl-gcc -static -O2 -mabi=ilp32f -march=rv32imafc_zicsr_zifencei_zba_zbb_zbs -o init init.c
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <mtd/mtd-abi.h>
#include <mtd/ubi-user.h>
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

static int read_text(const char *path, char *buf, size_t len)
{
    int fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    int n = read(fd, buf, len - 1);
    close(fd);
    if (n <= 0)
        return -1;
    buf[n] = 0;
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' ||
                     buf[n - 1] == ' ' || buf[n - 1] == '\t'))
        buf[--n] = 0;
    return n;
}

static long read_int(const char *path)
{
    char buf[32];
    if (read_text(path, buf, sizeof(buf)) < 0)
        return -1;
    return strtol(buf, NULL, 0);
}

static int wait_path(const char *path)
{
    for (int i = 0; i < 100; i++) {
        if (access(path, F_OK) == 0)
            return 0;
        usleep(200 * 1000);
    }
    return -1;
}

static int ensure_dir(const char *path)
{
    if (mkdir(path, 0755) != 0 && errno != EEXIST)
        return -1;
    struct stat st;
    if (stat(path, &st) != 0 || !S_ISDIR(st.st_mode))
        return -1;
    return 0;
}

/* Attach and mount the UBI data volume.  No explicit erase, delete or format
 * command is sent.  The kernel may initialize an all-empty MTD through its
 * empty-MTD path; non-UBI data is refused and left untouched.  Existing
 * Buildroot data is mounted read/write, while an empty UBI area gets one
 * dynamic volume named data. */
static int ubi_mount(void)
{
    struct mtd_info_user info;
    int fd = open("/dev/mtd1", O_RDWR);
    if (fd < 0)
        return -1;
    if (ioctl(fd, MEMGETINFO, &info) != 0) {
        close(fd);
        return -1;
    }
    close(fd);
    if (info.type != MTD_NORFLASH || info.size != 0x1e0000 ||
        info.erasesize != 0x10000)
        return -1;

    char name[32];
    if (read_text("/sys/class/mtd/mtd1/name", name, sizeof(name)) < 0 ||
        strcmp(name, "data") != 0)
        return -1;

    fd = open("/dev/ubi_ctrl", O_RDWR);
    if (fd < 0)
        return -1;
    struct ubi_attach_req req = {
        .ubi_num = 0,
        .mtd_num = 1,
        .vid_hdr_offset = 0,
        .max_beb_per1024 = 0,
        .disable_fm = 0,
        .need_resv_pool = 0,
        .padding = {0},
    };
    if (ioctl(fd, UBI_IOCATT, &req) != 0 && errno != EBUSY) {
        close(fd);
        return -1;
    }
    close(fd);

    if (wait_path("/sys/class/ubi/ubi0/volumes_count") != 0)
        return -1;
    long count = read_int("/sys/class/ubi/ubi0/volumes_count");
    if (count < 0)
        return -1;

    if (count == 0) {
        long avail = read_int("/sys/class/ubi/ubi0/avail_eraseblocks");
        long erasesize = read_int("/sys/class/ubi/ubi0/eraseblock_size");
        if (avail <= 0 || erasesize <= 0)
            return -1;

        fd = open("/dev/ubi0", O_RDWR);
        if (fd < 0)
            return -1;
        struct ubi_mkvol_req mk = {
            .vol_id = UBI_VOL_NUM_AUTO,
            .alignment = 1,
            .bytes = (int64_t)avail * erasesize,
            .vol_type = UBI_DYNAMIC_VOLUME,
            .flags = 0,
            .name_len = 4,
            .name = "data",
        };
        if (ioctl(fd, UBI_IOCMKVOL, &mk) != 0 && errno != EEXIST) {
            close(fd);
            return -1;
        }
        close(fd);
    }

    if (wait_path("/dev/ubi0") != 0)
        return -1;
    return mount("ubi0:data", "/overlay", "ubifs", MS_NOATIME, NULL);
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
    int persistent = 0;
    if (ubi_mount() == 0) {
        if (ensure_dir("/overlay/openwrt") == 0 &&
            ensure_dir("/overlay/openwrt/upper") == 0 &&
            ensure_dir("/overlay/openwrt/work") == 0) {
            persistent = 1;
            say("flash-init: persistent UBIFS overlay mounted\n");
        } else {
            umount("/overlay");
        }
    } else {
        say("flash-init: using tmpfs overlay\n");
    }

    if (persistent || mount("tmpfs", "/overlay", "tmpfs", MS_NOATIME,
                            "size=1024k,mode=0755") == 0) {
        if (persistent) {
            ret = mount("overlay", "/new", "overlay", MS_NOATIME,
                        "lowerdir=/rom,upperdir=/overlay/openwrt/upper,workdir=/overlay/openwrt/work");
        } else {
            mkdir("/overlay/upper", 0755);
            mkdir("/overlay/work", 0755);
            ret = mount("overlay", "/new", "overlay", MS_NOATIME,
                        "lowerdir=/rom,upperdir=/overlay/upper,workdir=/overlay/work");
        }
        if (ret == 0) {
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
