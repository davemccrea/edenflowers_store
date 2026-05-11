defmodule EdenflowersWeb.FaqLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-16 md:mb-20">{~t"Frequently Asked Questions"}</h1>

        <dl class="faq-list max-w-3xl">
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"How long will my flowers stay fresh?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Our flowers are carefully selected and arranged to last 5–7 days with proper care. We recommend changing the water every 2–3 days, trimming the stems, and keeping them away from direct sunlight and drafts."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"What is your delivery policy?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"We offer same-day delivery for orders placed before 2 PM on weekdays. For weekend deliveries, please place your order by Friday 2 PM. All our deliveries are carefully handled to ensure your flowers arrive in perfect condition."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"Can I include a personal message with my order?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Yes. You can add a personal message during checkout. We'll include it on a beautiful card with your delivery. Messages can be up to 200 characters."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"Do you offer subscription services?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Yes — we offer weekly, bi-weekly, and monthly subscriptions. You can tailor the cadence to your preferences. Subscribers receive 10% off all orders."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"What happens if I'm not home for delivery?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Our delivery team will attempt to leave your flowers in a safe, shaded location. If no suitable spot is available, they'll leave a note with instructions for redelivery. You can also specify delivery instructions during checkout."}
            </dd>
          </div>
        </dl>
      </.container>
    </Layouts.app>
    """
  end
end
