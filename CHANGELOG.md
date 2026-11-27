# Changelog

<!-- sprint-flow:changelog — i giorni li scrive ogni notte il timer di sprint-flow
     (proxmox_doctor, deploy/sprint-flow) dai commit: non modificarli a mano. -->

Cosa è cambiato, giorno per giorno, e chi l'ha fatto. Ogni argomento indica gli
agenti che hanno fatto i commit (trailer `Agent:`); «Dal backlog» elenca le voci
tolte da `BACKLOG.md` perché fatte. Il file parte dal 2026-11-25: per la storia
precedente valgono `git log` e le note delle release.

<!-- sprint-flow:inizio 44bb8c253d3b790d2382659c3bf9adae9359dad4 -->
<!-- sprint-flow:giorni -->
<!-- sprint-flow:ultimo 1acdd5edda5135ecb1bbb0732c2d7ef1460a83ed -->

## 2026-11-26
<!-- sprint-flow:giorno commit=4 testo=prod-default -->

**Progetto pronto per essere pubblico** — opencode
- Il progetto è stato rinominato in strix-halo-llm-recipe per rispettare la trademark policy e mantenere l'uso descrittivo di halogen recipe.
- Corretto un problema di sicurezza: il quadlet esponeva la porta 8731 su tutte le interfacce senza API key.
- Aggiunti i file necessari alla pubblicazione, come licenza, notice e README.

**Preflight distingue Windows, WSL2 e Linux** — opencode
- Il preflight ora decide la famiglia del sistema da uname -s, invece di basarsi solo su /proc/version.
- Windows e macOS ricevono un FAIL esplicito e non vengono più scambiati per Linux nativo.
- Evita che un controllo superficiale su Windows/Git Bash mostri un falso ok e nasconda il FAIL successivo.

**Contratto operativo e troubleshooting ampliato** — opencode
- AGENTS.md ora indica l'ordine dei passi, sei regole non negoziabili e una tabella sintomo -> dove guardare.
- Aggiunta la sezione su cosa non è un bug, per evitare interventi inutili.
- Il troubleshooting include due problemi incontrati davvero, tra cui il lingering senza loginctl enable-linger.

**Prompt di setup passo per passo** — opencode
- Nuovo docs/SETUP-PROMPT.md con otto passi dal clone al rapporto finale.
- Include la tabella dei FAIL di preflight e cosa dire all'operatore per ogni caso.
- In fondo ci sono tre comandi per passare il prompt a chi esegue il setup.

<!-- sprint-flow:giorni-fine -->
