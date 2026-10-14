/* Tutorial visual da aba Virada 2ºT: destaca cada bloco da aba (filtros,
   mapa, ranking, ficha e #metodo) com um cartão de descrição curta e botões
   Anterior/Próximo. Abre sozinho na primeira visita à aba e pode ser
   reaberto a qualquer momento pelo botão "Tutorial" na barra de filtros.
   Sem dependências: spotlight via box-shadow gigante no próprio alvo. */
(function () {
  'use strict';

  var CHAVE = 'painel-virada-tour-v1';

  var passos = [
    { alvo: null, titulo: 'Virada 2º turno em 6 passos',
      texto: 'Onde concentrar esforço para virar o 2º turno no DF: filtros, mapa, ranking de prioridade, ficha de campo e método. Leva menos de 1 minuto.' },
    { alvo: '.painel-virada-toolbar', titulo: 'Filtros',
      texto: 'Escolha a corrida, o tipo de mapa, a cor das RAs, a ordem do ranking, o cenário de 2º turno (p) e o mínimo de aptos por local.' },
    { alvo: '.painel-virada-card-mapa', titulo: 'Mapa da virada',
      texto: 'Cada bolha é um local de votação: tamanho = teto de virada; cor = situação no cenário. No modo Regiões administrativas, a cor pinta a RA pela métrica escolhida.' },
    { alvo: '.painel-virada-card-ranking', titulo: 'Ranking de prioridade',
      texto: 'Locais ordenados pelo IPV (potencial de virada). Clique numa linha para abrir a ficha e destacar o local no mapa; a planilha completa baixa em xlsx.' },
    { alvo: '.painel-virada-ficha-slot', titulo: 'Ficha do local',
      texto: 'Abre ao clicar num local: números do local, quem procurar, roteiro curto, mensagem pronta para WhatsApp e perfil PDAD-A 2024 da RA.' },
    { alvo: '.painel-virada-metodo', titulo: 'Como ler (#metodo)',
      texto: 'Fórmulas (V1 a V5, IPV), cenários e limitações dos dados. Consulte antes de usar qualquer número em material de campanha.' }
  ];

  var est = { ativo: false, i: 0, lista: [], alvo: null, foco: null,
              card: null, veu: null, raf: null };

  function visto() {
    try { return !!localStorage.getItem(CHAVE); } catch (e) { return true; }
  }
  function marcarVisto() {
    try { localStorage.setItem(CHAVE, '1'); } catch (e) { /* ok */ }
  }
  function abaVisivel() {
    var raiz = document.querySelector('.painel-virada-toolbar');
    return !!raiz && raiz.offsetParent !== null;
  }

  function construir() {
    est.veu = document.createElement('div');
    est.veu.className = 'painel-tour-veu';
    est.veu.setAttribute('aria-hidden', 'true');

    est.card = document.createElement('div');
    est.card.className = 'painel-tour-card';
    est.card.setAttribute('role', 'dialog');
    est.card.setAttribute('aria-modal', 'true');
    est.card.setAttribute('aria-labelledby', 'painel-tour-titulo');
    est.card.setAttribute('tabindex', '-1');
    est.card.innerHTML =
      '<button type="button" class="painel-tour-fechar" aria-label="Fechar o tutorial">&times;</button>' +
      '<h4 id="painel-tour-titulo"></h4>' +
      '<p></p>' +
      '<div class="painel-tour-rodape">' +
      '<span class="painel-tour-passos"></span>' +
      '<span class="painel-tour-btns">' +
      '<button type="button" class="btn btn-default btn-sm painel-tour-ant">Anterior</button>' +
      '<button type="button" class="btn btn-primary btn-sm painel-tour-prox">Próximo</button>' +
      '</span></div>';

    est.card.querySelector('.painel-tour-fechar').addEventListener('click', function () { fechar(); });
    est.card.querySelector('.painel-tour-ant').addEventListener('click', anterior);
    est.card.querySelector('.painel-tour-prox').addEventListener('click', proximo);
    est.veu.addEventListener('click', function () { fechar(); });
  }

  function posicionar() {
    if (!est.ativo || !est.alvo || est.alvo === est.card) return;
    var r = est.alvo.getBoundingClientRect();
    var card = est.card, cw = card.offsetWidth, ch = card.offsetHeight;
    var m = 12, vw = window.innerWidth, vh = window.innerHeight;
    var topo;
    if (r.bottom + ch + 2 * m < vh) topo = r.bottom + m;
    else if (r.top - ch - 2 * m > 0) topo = r.top - ch - m;
    else topo = Math.max(m, (vh - ch) / 2);
    var esq = Math.max(m, Math.min(r.left + Math.max(0, (r.width - cw) / 2),
      vw - cw - m));
    card.style.top = Math.round(topo) + 'px';
    card.style.left = Math.round(esq) + 'px';
  }

  function aoMudar() {
    if (est.raf) cancelAnimationFrame(est.raf);
    est.raf = requestAnimationFrame(posicionar);
  }

  function aoTeclado(ev) {
    if (ev.key === 'Escape') fechar();
    else if (ev.key === 'ArrowRight') proximo();
    else if (ev.key === 'ArrowLeft') anterior();
  }

  function mostrarPasso(i) {
    if (est.alvo) est.alvo.classList.remove('painel-tour-alvo');
    est.i = i;
    var passo = est.lista[i];
    var alvo = passo.alvo ? document.querySelector(passo.alvo) : null;
    est.alvo = alvo || est.card;
    est.alvo.classList.add('painel-tour-alvo');

    var n = est.lista.length;
    est.card.querySelector('h4').textContent = passo.titulo;
    est.card.querySelector('p').textContent = passo.texto;
    est.card.querySelector('.painel-tour-passos').textContent =
      'Passo ' + (i + 1) + ' de ' + n;
    est.card.querySelector('.painel-tour-ant').style.visibility =
      i === 0 ? 'hidden' : 'visible';
    est.card.querySelector('.painel-tour-prox').textContent =
      i === n - 1 ? 'Concluir' : 'Próximo';

    est.card.style.transform = '';
    if (alvo) {
      alvo.scrollIntoView({ behavior: 'smooth', block: 'center' });
      posicionar();
      setTimeout(posicionar, 380);
    } else {
      est.card.style.top = '50%';
      est.card.style.left = '50%';
      est.card.style.transform = 'translate(-50%, -50%)';
    }
    est.card.focus({ preventScroll: true });
  }

  function proximo() {
    if (!est.ativo) return;
    if (est.i >= est.lista.length - 1) fechar();
    else mostrarPasso(est.i + 1);
  }
  function anterior() {
    if (!est.ativo || est.i === 0) return;
    mostrarPasso(est.i - 1);
  }

  function iniciar() {
    if (est.ativo || !abaVisivel()) return;
    est.lista = passos.filter(function (p) {
      return !p.alvo || document.querySelector(p.alvo);
    });
    if (!est.lista.length) return;
    if (!est.card) construir();
    est.ativo = true;
    document.body.appendChild(est.veu);
    document.body.appendChild(est.card);
    est.foco = document.activeElement;
    window.addEventListener('scroll', aoMudar, true);
    window.addEventListener('resize', aoMudar);
    document.addEventListener('keydown', aoTeclado);
    mostrarPasso(0);
  }

  function fechar() {
    if (!est.ativo) return;
    est.ativo = false;
    if (est.alvo) est.alvo.classList.remove('painel-tour-alvo');
    est.alvo = null;
    est.card.remove();
    est.veu.remove();
    if (est.raf) cancelAnimationFrame(est.raf);
    window.removeEventListener('scroll', aoMudar, true);
    window.removeEventListener('resize', aoMudar);
    document.removeEventListener('keydown', aoTeclado);
    marcarVisto();
    if (est.foco && est.foco.focus) {
      try { est.foco.focus({ preventScroll: true }); } catch (e) { /* ok */ }
    }
  }

  function talvezAutoAbrir() {
    if (visto() || est.ativo || !abaVisivel()) return;
    setTimeout(function () {
      if (!visto() && !est.ativo && abaVisivel()) iniciar();
    }, 900);
  }

  document.addEventListener('click', function (ev) {
    var botao = ev.target.closest('.painel-virada-tour-btn');
    if (botao) {
      ev.preventDefault();
      if (est.ativo) fechar();
      iniciar();
      return;
    }
    var aba = ev.target.closest('#painel_nav a[data-value="virada"]');
    if (aba) talvezAutoAbrir();
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', talvezAutoAbrir);
  } else {
    talvezAutoAbrir();
  }
})();
