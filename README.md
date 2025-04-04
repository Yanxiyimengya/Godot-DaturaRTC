# Godot-DaturaRTC

This repository aims to achieve real-time network voice communication through Godot and implement voice data transmission through a custom UDP protocol.

# Introduction

Godot DaturaRTC (DaturaVoice) is a real-time voice call plugin implemented through GodotScript.

It transmits audio data via the UDP network protocol to achieve multi-terminal voice calls.

# How to use it?

Download DaturaRTC

You can directly download the ZIP compressed package file.

Add the addons to the project

Copy the "daturavoice" folder in the addons to the addons directory of your own project.

Enable DaturaVoice in Project > Project Settings > Plugins.

Add the DaturaAudioMicrophone node to your project.

Create a DaturaAudioMicrophone node under the scene tree.

Create a DaturaUDP server/client

Use the create_server/create_client under DaturaAudioMicrophone to create a network service.

# About

[Author's Bilibili Homepage](https://space.bilibili.com/481430814)
