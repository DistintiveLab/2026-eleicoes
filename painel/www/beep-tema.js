/* Núcleo de tema do beep: alterna as paletas gov.br e preto-e-branco
   Distintive (classe beep-pb no <body>), persiste a escolha em
   localStorage (chave "beep_paleta"; sem escolha salva vale o
   data-paleta da div #beep_tema_raiz) e atualiza rotulo/aria de todos
   os botões .beep-tema-btn. A cada aplicação despacha o evento
   "beep:paleta" no document — consumidores (ex.: o painel, que recore
   gráficos no servidor) escutam o evento em vez de duplicar o toggle. */
(function () {
  'use strict';
  var atual = 'govbr';
  var paletas = ['govbr', 'pb', 'brasil'];
  var rotulos = {
    govbr: 'Preto e branco',
    pb: 'Brasil (vermelho)',
    brasil: 'Cores Gov.br'
  };
  var titulos = {
    govbr: 'Mudar para preto e branco com roxo Distintive',
    pb: 'Mudar para a paleta Brasil (vermelho, fundo branco)',
    brasil: 'Mudar para a paleta Gov.br (azul)'
  };

  function aplicar(paleta) {
    atual = paletas.indexOf(paleta) >= 0 ? paleta : 'govbr';
    document.body.classList.toggle('beep-pb', atual === 'pb');
    document.body.classList.toggle('beep-brasil', atual === 'brasil');
    try { localStorage.setItem('beep_paleta', atual); } catch (e) { /* ok */ }
    var proximo = rotulos[paletas[(paletas.indexOf(atual) + 1) % paletas.length]];
    var botoes = document.querySelectorAll('.beep-tema-btn');
    for (var i = 0; i < botoes.length; i++) {
      botoes[i].textContent = proximo;
      botoes[i].setAttribute('aria-pressed', atual === 'govbr' ? 'false' : 'true');
      botoes[i].title = titulos[atual];
    }
    document.dispatchEvent(
      new CustomEvent('beep:paleta', { detail: { paleta: atual } }));
  }

  function inicial() {
    var salva = null;
    try { salva = localStorage.getItem('beep_paleta'); } catch (e) { /* ok */ }
    if (paletas.indexOf(salva) >= 0) return salva;
    var raiz = document.getElementById('beep_tema_raiz');
    var param = raiz ? raiz.getAttribute('data-paleta') : null;
    return paletas.indexOf(param) >= 0 ? param : 'govbr';
  }

  document.addEventListener('click', function (evento) {
    var botao = evento.target.closest
      ? evento.target.closest('.beep-tema-btn')
      : null;
    if (botao) {
      evento.preventDefault();
      aplicar(atual === 'pb' ? 'govbr' : 'pb');
    }
  });

  function inicializar() { aplicar(inicial()); }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inicializar);
  } else {
    inicializar();
  }
})();
