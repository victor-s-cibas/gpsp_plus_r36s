# gpSP Plus Core Manager for R36S (ArkOS / dArkOS)

Bring **real Game Boy Advance Link Cable emulation** to your retro handheld! 

This tool installs the **gpSP+** core for RetroArch 32-bit and automatically configures EmulationStation to use it for GBA games. 

The main goal of this project is to enable **True Multiplayer**. Just like the original GBA Link Cable (or modern Android emulators), this core allows you to connect multiple devices locally. You can now trade Pokémon, battle your friends, and play multiplayer GBA games seamlessly on your R36S!

## 🌐 Understanding RetroArch Netplay & Relay Servers

To make multiplayer work, this core relies on **RetroArch's Netplay**, a built-in feature that synchronizes multiple devices over a network so they can play together as if they were connected to the same console. 

Depending on where you are playing, you will need to adjust the **Relay Server** settings in RetroArch:

* **Local Play (Relay Server OFF - No Internet Needed):** If you and your friends are connected to the same local network (such as a home router or a mobile hotspot), you should **turn OFF the Relay Server**. By disabling it, the consoles will connect directly to each other via their local IP addresses. This provides a flawless, zero-lag experience and **does not require an active internet connection**.
* **Online Play (Relay Server ON):** If you want to play with someone far away over the internet, you can **turn ON the Relay Server** to easily bypass router and firewall restrictions. 
  * ⚠️ **ATTENTION:** When using a Relay Server, make sure to select a server located in the correct country (or the one closest to both players). Choosing a distant server will result in high ping, which causes noticeable input lag, stuttering, and potential disconnections.

## 🎮 Compatibility

This script was specifically developed and tested for the **R36S** handheld console.

It should work out of the box on any **ArkOS** build or its community variants, including:
- ArkOS
- dArkOSr
- dArkOSen
- dArkOSre
- dArkOS4clone

## ⚠️ IMPORTANT: Menu Controls

Because of how the R36S button layout is mapped in the system menus, the confirm and cancel buttons might feel "inverted" compared to standard layouts. 

Please keep this in mind when navigating the script menu:
>  **Press `B` to CONFIRM / SELECT**

>  **Press `A` to GO BACK / CANCEL**

*Note: The script includes a confirmation prompt when exiting so you don't accidentally close it if you press the wrong button.*

## 🛠️ Installation Guide

We made the installation process as easy as possible! Just follow these steps:

1. 📥 **Download** the latest release `.zip` file from this repository.
2. 📦 **Extract** the `.zip` file on your computer. 
3. 💾 **Copy to SD Card:** Insert your console's SD card (the one with your games, usually named `EASYROMS` or `roms`) into your PC.
4. 🧩 **Move to Tools:** Find the `tools` folder inside the `roms` partition and paste **both** the extracted script and the `gpsp_plus` folder inside it.

**👀 Here is how your folder structure should look like:**

```text
🗂️ SD_CARD (roms)
 └── 📁 tools
      ├── 📁 gpsp_plus
      │    ├── ⚙️ gpsp_plus_libretro.so
      │    └── ⚙️ gpsp_plus_libretro.info
      ├── 📜 install_gpsp_plus.sh
      └── // (other tools you might already have...)
```

5. 🕹️ **Boot your R36S:** Safely eject the SD card from your PC, put it back into your console, and turn it on.
6. 🚀 **Run the Installer:** Scroll through your console's main systems until you find the **Tools** section (Options menu). Find the gpSP+ script you just added, open it, and let the magic happen!

## 🚀 Usage

Once you open the script on your console:
1. Use the D-Pad to navigate.
2. Select **"1 - Install gpSP+ (RetroArch 32-bit)"** and press **`B`**.
3. Wait a few seconds while it copies the files and updates your `es_systems.cfg` file.
4. When prompted, select **"Restart ES"** (pressing **`B`**).
5. Done! Your GBA games will now launch using the gpSP+ core, ready for Link Cable multiplayer.

If you ever want to revert back to the default emulator, simply run the script again and select the **Uninstall** option.

## 🙏 Credits & Acknowledgements

A special thanks to the **RParadise Team / Koriki Project** for providing the compiled `gpSP+` core used in this package.
* **Core Source:** [gpsp_plus_libretro.so.zip](https://rparadise-team.github.io/Koriki/armhf/gpsp_plus_libretro.so.zip)
