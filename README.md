# ++Party

## Clone and Run
Make sure you are using Zig version `0.12.0` and then run the following commands:
```bash
git clone git@github.com:INDA23PlusPlus/plusplusparty.git --recursive
cd plusplusparty
zig build run
```
To run a specific example, use the `--minigame <name>` argument. For example:
```bash
zig build run -- --minigame example
```
Some available minigames are:
- Menu (`menu`)
- Tron (`tron`)
- Morse code (`morsecode`)
- Hot n' steamy (`hns`)
- Smash (`smash`)
- Kattis (`kattis`)

### Launching a Server (Multiplayer)
To run as a server, use run-server:
```bash
zig build run-server
```

### Launching a Client (Multiplayer)
To run as a client, use run-client:
```bash
zig build run-client
```

### Usage with nix
Requirements: nix installed with experimental features flakes and nix-command enabled

To start a shell with all dev, build and runtime dependencies available including the correct version of the zig compiler and zls, use nix develop:
```bash
nix develop
```
All the commands described above can then be run as normal.
Only works for linux right now. Package and app outputs will be added later.

