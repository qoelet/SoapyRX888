# SoapyRX888

Unsupported fork of [https://github.com/cozycactus/SoapyRX888](https://github.com/cozycactus/SoapyRX888).

Based on https://github.com/steve-m/librtlsdr.

## What?

This is my attempt to get my RX888 MKII working on MacOS. The original SoapyRX888 has not been worked on since 2023, and
as the following issues show, support on Linux and MacOS is "spotty" at best,

- https://github.com/cozycactus/SoapyRX888/issues/1
- https://github.com/pothosware/SoapySDR/issues/467
- https://github.com/pothosware/SoapySDR/issues/386

The patch in this fork is largely based off [hz12's patch](https://groups.io/g/NextGenSDRs/message/1606); direct [pastebin link here](https://pastebin.com/zjRz62sf).
I added a `build.sh` here that I used to get everything working (assumes radioconda as a dependency). I have tested using `gqrx` and a YouLoop antenna.

If you are considering a RX888 for HF listening, I highly recommend you read [RX888 issues](https://docs.google.com/document/d/1hG634yVkBBIMykmmnosUxw7gumAoc3z1SmWDrH1TucM/), written by the
developers of SatDump and SDR++. What they recommend is buy something like an Airspy instead. But if you already bought one and want to get it working on MacOS, then
hopefully this fork might be a useful starting point.

Obviously if you are using RX888 for other purposes (analyzing the whole spectrum), then that's a different story. Possibly that's where the direct sampling starts to
make sense :)

**I am not maintaining this**, the modifications are provided as is for reference only.
