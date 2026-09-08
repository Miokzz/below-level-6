# BELOW LEVEL 6

Jogo de terror psicológico em primeira pessoa para **Godot 4.5.2**.
Você é um técnico enviado ao setor subterrâneo da Meridian durante a madrugada.
A ordem de serviço pede energia, refrigeração e rede. A instalação responde às
suas intervenções.

Esta versão continua a instalação procedural, controller, entidade e biblioteca
sonora do repositório original. Inclui uma campanha curta com introdução no
elevador, exploração, três puzzles ambientais, vigilância, perseguição e final.
O áudio e os textos do jogo estão em inglês.

## Jogar uma build

Extraia o ZIP completo e abra `BELOW LEVEL 6.exe` no Windows x64 ou
`BELOW LEVEL 6.x86_64` no Linux x64. A build inclui os recursos do jogo; não exige
Godot, Python, servidor ou navegador.

Na distribuição Linux, caso necessário: `chmod +x "BELOW LEVEL 6.x86_64"`.
O renderizador é Compatibility/OpenGL 3.3. O jogo não usa microfone.

## Abrir o projeto

1. Instale o Godot **4.5.2 Standard**, sem .NET.
2. Importe `project.godot` no gerenciador do Godot e aguarde a importação do áudio.
3. Pressione **F6** com `scenes/main.tscn` aberta, ou **F5** para iniciar o projeto.
4. Escolha **NEW GAME**. O elevador inicia a descida; depois as portas abrem.

Também é possível executar `godot --path .` na pasta do repositório.
Não há addons ou dependências externas em tempo de execução.

## Controles e progresso

| Controle | Ação |
| --- | --- |
| WASD / mouse | Andar / olhar |
| E | Usar o objeto sob a mira |
| Shift | Correr |
| Ctrl / C | Agachar segurando / alternar |
| F | Lanterna |
| Esc | Fechar documento, voltar ou pausar |

A ordem de serviço aparece discretamente no alto da tela. As placas identificam
os setores e os documentos próximos aos mecanismos explicam os puzzles. Erros de
sequência podem ser corrigidos nos próprios controles. Documentos e terminais
pausam a simulação; a sequência de fuga usa mecanismos diretamente no mundo.

**CONTINUE** aparece disponível quando há checkpoint válido. O jogo salva
reparos, itens, eventos e progresso em posições seguras. Durante a perseguição,
a recuperação retorna à entrada do núcleo com os reparos preservados.
Configurações ficam em arquivo separado. Existe recuperação de backup para um
checkpoint danificado. Uma campanha concluída libera um novo jogo pelo menu.

Os arquivos ficam na pasta `user://` do Godot: em geral
`%APPDATA%/Godot/app_userdata/BELOW LEVEL 6/` no Windows e
`~/.local/share/godot/app_userdata/BELOW LEVEL 6/` no Linux.

## Verificar e exportar

Com Python 3, o instalador opcional baixa a versão fixada e verifica os hashes
SHA512 oficiais antes de extrair os arquivos:

```sh
python3 tools/setup_godot.py --templates
python3 tools/verify.py --godot .tools/godot/Godot_v4.5.2-stable_linux.x86_64
python3 tools/verify.py --godot .tools/godot/Godot_v4.5.2-stable_linux.x86_64 --native
python3 tools/package.py --godot .tools/godot/Godot_v4.5.2-stable_linux.x86_64
```

No Windows, use `python` e o executável
`.tools/godot/Godot_v4.5.2-stable_win64_console.exe`. O instalador PowerShell
original `tools/setup_godot.ps1` também continua disponível para exportação Windows.
O download dos templates de exportação é de aproximadamente 1,35 GB.

`--native` abre uma janela e percorre a campanha usando o controller, a tecla E
e os botões da UI. Requer um display nativo ou Xvfb; o driver headless não captura
o mouse e não serve para esse teste de entrada. Os demais testes podem rodar sem
janela. Logs e capturas ficam em `test-output/`, fora do Git e da distribuição.

As builds e ZIPs são gerados em `dist/`. A biblioteca de áudio já está versionada;
não é necessário executar os geradores. Regeneração opcional requer NumPy, SciPy
e Pillow; as falas originais usam a API de voz do Windows.

## Arquitetura e origem dos recursos

- `environment/`: instalação, portas, elevador, materiais, colisões e navegação.
- `player/`, `ai/`, `narrative/`: movimento, observação, perseguição e eventos.
- `systems/`: sessão, progressão, checkpoints e configurações.
- `puzzles/`: estado e validação dos reparos.
- `ui/`, `audio/`: interface reutilizável e ciclo de sons/falas/legendas.
- `scenes/main.tscn`: ponto de entrada.
- `tests/` e scripts `check_*`, `verify_*`, `test_*`: verificações reproduzíveis.

[Auditoria do estado original](docs/AUDIT.md), [arquitetura](docs/ARCHITECTURE.md)
e [procedência dos assets](docs/ASSETS.md) documentam a recuperação.
O briefing em `docs/BRIEF.md` é um registro histórico de intenção; não é uma lista
de funcionalidades já entregues. Recursos opcionais como microfone e reflexo
atrasado não são expostos na experiência atual.

As licenças do Godot e de suas dependências estão em `docs/licenses/` e acompanham
as builds em `licenses/`. O projeto não declara uma licença geral de código
aberto para seu código e assets originais.
