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
              {~t"Eden Flowers' arrangements last 5–7 days with proper care. Change the water every 2–3 days, trim the stems, and keep them away from direct sunlight and drafts."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"What is your delivery policy?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Same-day delivery is available for orders placed before 2 PM on weekdays. For weekend deliveries, please order by Friday 2 PM. Every delivery is handled carefully so the flowers arrive in perfect condition."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"Can I include a personal message with my order?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Yes. Add a personal message during checkout — it'll be included on a card with the delivery. Messages can be up to 200 characters."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"Do you offer subscription services?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"Yes — weekly, bi-weekly, and monthly subscriptions are available, with the cadence tailored to your preferences. Subscribers receive 10% off all orders."}
            </dd>
          </div>
          <div class="faq-list__item">
            <dt>
              <h2 class="faq-list__question">{~t"What happens if I'm not home for delivery?"}</h2>
            </dt>
            <dd class="faq-list__answer">
              {~t"If you're not in, the flowers will be left in a safe, shaded spot. If no suitable spot is available, a note with redelivery instructions will be left. You can also specify delivery instructions during checkout."}
            </dd>
          </div>
        </dl>
      </.container>
    </Layouts.app>
    """
  end
end
