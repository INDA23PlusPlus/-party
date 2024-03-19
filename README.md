# ++Party

## Clone and Run
```bash
git clone git@github.com:INDA23PlusPlus/plusplusparty.git --recursive
cd plusplusparty
zig build run
```

## Desing Doc
måste ha:
- [ ] 2D Graphics
- [ ] Networking
- [ ] Pysics
- [ ] Collision
- [ ] Asset loading
- [ ] ECS
- [ ] UI
- [ ] Input modul
- [ ] Event Loop
- [ ] Main Menu / start games / next game screen / score

Nice to have:
- [ ] Ljud

Ska icke
- [ ] inte 3D
- [ ] allt som raylib gör

ECS: (first Draft)
- Position
- Transform (endast för dynamiska saker)
    - sub-pixel position
    - velocitiy
    - acceleration
- Collider
    - dim
- Texture
    - texture pointer
    - dim
- Text
    - text
    - dim

Assets gör inte vi

raylib för allt

zig master branch

alla ser exakt samma sak i mutliplayer

låst till 60fps

pusha endast till main om det compilerar.

annvänd zig formater

Par vis utveckling av minigames när vi är klara med grundläggande Game Engine 

Input:
8 riktningar och två knappar är all input

Mini Game Ideas:
- Fråga Jonatan om hjälp
- Typ racer koncept t.ex. skriva ett tal i binärt så snabbt som möjligt
- simple smash 
- Submitta till kattis 100% rng om den lyckas 
- måndagsstäd
