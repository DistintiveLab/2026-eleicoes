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

  function aplicar(paleta) {
    atual = paleta === 'pb' ? 'pb' : 'govbr';
    document.body.classList.toggle('beep-pb', atual === 'pb');
    try { localStorage.setItem('beep_paleta', atual); } catch (e) { /* ok */ }
    var botoes = document.querySelectorAll('.beep-tema-btn');
    for (var i = 0; i < botoes.length; i++) {
      botoes[i].textContent = atual === 'pb' ? 'Cores Gov.br' : 'Preto e branco';
      botoes[i].setAttribute('aria-pressed', atual === 'pb' ? 'false' : 'true');
      botoes[i].title = atual === 'pb'
        ? 'Mudar para a paleta Gov.br (azul)'
        : 'Mudar para preto e branco com roxo Distintive';
    }
    document.dispatchEvent(
      new CustomEvent('beep:paleta', { detail: { paleta: atual } }));
  }

  function inicial() {
    var salva = null;
    try { salva = localStorage.getItem('beep_paleta'); } catch (e) { /* ok */ }
    if (salva === 'govbr' || salva === 'pb') return salva;
    var raiz = document.getElementById('beep_tema_raiz');
    var param = raiz ? raiz.getAttribute('data-paleta') : null;
    return param === 'pb' ? 'pb' : 'govbr';
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
