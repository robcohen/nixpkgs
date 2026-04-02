# AMD Ryzen AI NPU support
#
# This module configures NixOS to work with AMD Ryzen AI NPUs (XDNA 2 architecture).
# Supported hardware:
# - Strix Point (17f0_10) - firmware available
# - Strix Halo (17f0_11) - firmware available
# - Krackan Point (17f0_20) - awaiting firmware release
#
# Requirements:
# - Kernel 6.14+ (amdxdna driver in mainline)
# - linux-firmware 20240811+ (NPU firmware)
# - User in 'video' group (or configured group)

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.amd-npu;
in
{
  options.hardware.amd-npu = {
    enable = lib.mkEnableOption "AMD Ryzen AI NPU support";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xrt-amdxdna;
      defaultText = lib.literalExpression "pkgs.xrt-amdxdna";
      description = "The XRT package with AMDXDNA plugin to use.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "video";
      description = "Group granted access to NPU device and elevated memlock limits.";
    };

    enableDevTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to include XRT development tools (xrt-smi, xclbinutil) in the system path.
        Disable this for minimal production installations.
      '';
    };

    memlockLimit = lib.mkOption {
      type = lib.types.either lib.types.ints.positive (lib.types.enum [ "unlimited" ]);
      default = "unlimited";
      description = ''
        Memory lock limit for NPU buffer allocation.
        The NPU driver needs to mmap large buffers (64MB+).
        Set to "unlimited" or a specific number of bytes.
      '';
    };

    kernelModule = lib.mkOption {
      type = lib.types.str;
      default = "amdxdna";
      description = "Kernel module name for the AMD NPU driver.";
    };

    extraUdevRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional udev rules for NPU device configuration.";
    };

    firmwareCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to add a systemd service that checks for NPU firmware on boot.
        Logs warnings if firmware is missing or hardware is unsupported.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure amdxdna kernel module is loaded
    boot.kernelModules = [ cfg.kernelModule ];

    # SVA (Shared Virtual Addressing) requires IOMMU translated mode, not passthrough
    boot.kernelParams = [ "iommu.passthrough=0" ];

    # Add udev rules for NPU device access
    services.udev.extraRules = ''
      # AMD NPU (amdxdna) - allow users in ${cfg.group} group
      SUBSYSTEM=="accel", KERNEL=="accel[0-9]*", GROUP="${cfg.group}", MODE="0660"
      ${cfg.extraUdevRules}
    '';

    # Increase locked memory limit for NPU buffer allocation
    # The NPU driver needs to mmap large buffers (64MB+)
    security.pam.loginLimits = [
      {
        domain = "@${cfg.group}";
        type = "soft";
        item = "memlock";
        value = toString cfg.memlockLimit;
      }
      {
        domain = "@${cfg.group}";
        type = "hard";
        item = "memlock";
        value = toString cfg.memlockLimit;
      }
    ];

    # Add combined XRT+plugin to system packages
    environment.systemPackages = lib.mkIf cfg.enableDevTools [ cfg.package ];

    # Set up environment for XRT
    environment.variables = {
      XILINX_XRT = "${cfg.package}/opt/xilinx/xrt";
    };

    # Assertions to help users diagnose issues
    assertions = [
      {
        assertion = config.boot.kernelPackages.kernelAtLeast "6.10";
        message = ''
          AMD NPU support requires kernel 6.10 or newer.
          The amdxdna driver is in mainline kernel starting from 6.14.
          For kernels 6.10-6.13, you may need to build the driver separately.
        '';
      }
    ];

    # Warnings for common configuration issues
    warnings = lib.optional (
      cfg.group != "video" && !(builtins.elem cfg.group config.users.groups)
    ) "hardware.amd-npu.group is set to '${cfg.group}' but this group doesn't exist. NPU access may not work.";

    # Firmware check service - detects hardware and warns about missing firmware
    systemd.services.amd-npu-firmware-check = lib.mkIf cfg.firmwareCheck {
      description = "AMD NPU Firmware Compatibility Check";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.pciutils
        pkgs.coreutils
        pkgs.gnugrep
      ];
      script = ''
        check_npu_firmware() {
          local pci_id="1022:17f0"
          local device_path

          # Find the NPU device
          device_path=$(lspci -nn 2>/dev/null | grep -i "$pci_id" | head -1)

          if [ -z "$device_path" ]; then
            # Check for XDNA 1 (Phoenix/Hawk Point)
            if lspci -nn 2>/dev/null | grep -qi "1022:1502"; then
              echo "WARNING: Detected XDNA 1 NPU (Phoenix/Hawk Point)"
              echo "WARNING: This module only supports XDNA 2 architecture"
              echo "WARNING: See: https://github.com/amd/xdna-driver for XDNA 1 support"
              return 1
            fi
            echo "INFO: No AMD NPU detected (PCI ID $pci_id not found)"
            return 0
          fi

          echo "INFO: Found NPU: $device_path"

          # Extract revision from lspci output
          local revision
          revision=$(echo "$device_path" | grep -oP '\(rev \K[0-9a-f]+' | head -1)

          if [ -z "$revision" ]; then
            echo "WARNING: Could not determine NPU revision"
            return 1
          fi

          echo "INFO: NPU revision: $revision"

          # Check firmware availability based on revision
          case "$revision" in
            10)
              if [ -f /run/current-system/firmware/amdnpu/17f0_10/npu.sbin ]; then
                echo "OK: Strix Point B0 firmware found (17f0_10)"
              else
                echo "WARNING: Strix Point B0 firmware not found"
                echo "WARNING: Expected: /run/current-system/firmware/amdnpu/17f0_10/npu.sbin"
                echo "WARNING: Ensure linux-firmware 20240811+ is installed"
              fi
              ;;
            11)
              if [ -f /run/current-system/firmware/amdnpu/17f0_11/npu.sbin ]; then
                echo "OK: Strix Halo firmware found (17f0_11)"
              else
                echo "WARNING: Strix Halo firmware not found"
                echo "WARNING: Expected: /run/current-system/firmware/amdnpu/17f0_11/npu.sbin"
                echo "WARNING: Ensure linux-firmware 20240811+ is installed"
              fi
              ;;
            20)
              echo "WARNING: Krackan Point detected (revision 20)"
              echo "WARNING: AMD has NOT released firmware for this hardware yet"
              echo "WARNING: Track progress: https://github.com/amd/xdna-driver/issues"
              echo "WARNING: Track progress: https://gitlab.com/kernel-firmware/linux-firmware"
              echo "WARNING: NPU will not function until AMD releases 17f0_20 firmware"
              ;;
            *)
              echo "WARNING: Unknown NPU revision: $revision"
              echo "WARNING: This hardware may not be supported yet"
              ;;
          esac

          # Check if device node exists
          if [ -e /dev/accel/accel0 ]; then
            echo "OK: NPU device node exists at /dev/accel/accel0"
          else
            echo "WARNING: NPU device node not found at /dev/accel/accel0"
            echo "WARNING: Check: lsmod | grep amdxdna"
            echo "WARNING: Check: dmesg | grep -i amdxdna"
          fi
        }

        check_npu_firmware
      '';
    };
  };

  meta.maintainers = with lib.maintainers; [ robcohen ];
}
