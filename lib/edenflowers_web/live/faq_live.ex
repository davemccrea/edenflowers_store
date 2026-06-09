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

        <dl class="max-w-3xl">
          <.faq_item question={~t"How long will my flowers stay fresh?"}>
            {~t"Eden Flowers' arrangements last 5–7 days with proper care. Change the water every 2–3 days, trim the stems, and keep them away from direct sunlight and drafts."}
          </.faq_item>
          <.faq_item question={~t"What is your delivery policy?"}>
            {~t"Same-day delivery is available for orders placed before 2 PM on weekdays. For weekend deliveries, please order by Friday 2 PM. Every delivery is handled carefully so the flowers arrive in perfect condition."}
          </.faq_item>
          <.faq_item question={~t"Can I include a personal message with my order?"}>
            {~t"Yes. Add a personal message during checkout — it'll be included on a card with the delivery. Messages can be up to 200 characters."}
          </.faq_item>
          <.faq_item question={~t"Do you offer subscription services?"}>
            {~t"Yes — weekly, bi-weekly, and monthly subscriptions are available, with the cadence tailored to your preferences. Subscribers receive 10% off all orders."}
          </.faq_item>
          <.faq_item question={~t"What happens if I'm not home for delivery?"}>
            {~t"If you're not in, the flowers will be left in a safe, shaded spot. If no suitable spot is available, a note with redelivery instructions will be left. You can also specify delivery instructions during checkout."}
          </.faq_item>
        </dl>
      </.container>
    </Layouts.app>
    """
  end

  attr :question, :string, required: true
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <div class="py-8 border-t border-base-content/12 last:border-b">
      <dt>
        <h2 class="font-serif text-xl leading-snug md:text-2xl mb-3.5">{@question}</h2>
      </dt>
      <dd class="font-sans text-[1.0625rem] leading-[1.6] text-base-content max-w-[60ch]">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end
end
