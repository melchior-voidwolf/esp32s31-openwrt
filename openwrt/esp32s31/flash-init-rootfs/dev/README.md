# initramfs device nodes

The release archive intentionally does not include privileged device nodes.
When preparing a custom initramfs, create the console node as root:

```sh
mkdir -p dev
mknod -m 600 dev/console c 5 1
```

Do not extract this directory as an ordinary file if your initramfs builder
expects a real character device.
