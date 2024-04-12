# ++Party

## Clone and run
Make sure you are using the right Zig version `0.12.0-dev.3412+54c08579e` and then run the following commands:
```bash
git clone git@github.com:INDA23PlusPlus/plusplusparty.git --recursive
cd plusplusparty
zig build run
```
To run a specific example, use the `-Dminigame=<name>` flag. For example:
```bash
zig build run -Dminigame=example
```
To run as a server, use run-server:
```bash
zig build run-server
```
can also use the `-Dminigame=<name>` flag to run a specific minigame as a server.
