# ++Party

## Clone and Run
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
Some available minigames are:
- Menu (`menu`)
- Tron (`tron`)
- Morse code (`morsecode`)
- Hot n' steamy (`hns`)

To run as a server, use run-server:
```bash
zig build run-server
```
can also use the `-Dminigame=<name>` flag to run a specific minigame as a server.

# Credits
GUI Assets:
  * License Link: https://creativecommons.org/licenses/by/4.0/
  * Licensor Owner: Crusenho Agus Hennihuno
  * Licensor Store Link: https://crusenho.itch.io
