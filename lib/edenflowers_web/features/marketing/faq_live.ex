defmodule EdenflowersWeb.Marketing.FaqLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-16 md:mb-20">
          {~t"Frequently Asked Questions"}
        </h1>

        <dl class="max-w-3xl">
          <.faq_item question={~t"How long will my flowers stay fresh?"}>
            {~t"Eden Flowers' arrangements last 5–7 days with proper care. Change the water every 2–3 days, trim the stems, and keep them away from direct sunlight and drafts."}
          </.faq_item>
          <.faq_item question={~t"What is your delivery policy?"}>
            {~t"Same-day delivery is available for orders placed before 2 PM on weekdays. For weekend deliveries, please order by Friday 2 PM. Every delivery is handled carefully so the flowers arrive in perfect condition."}
          </.faq_item>
          <.faq_item question={~t"Can I include a personal message with my order?"}>
            {~t"Yes. Add a personal message during checkout and it'll be included on a card with the delivery. Messages can be up to 200 characters."}
          </.faq_item>
          <.faq_item question={~t"What happens if I'm not home for delivery?"}>
            {~t"If you're not in, the flowers will be left in a safe, shaded spot. If no suitable spot is available, a note with redelivery instructions will be left. You can also specify delivery instructions during checkout."}
          </.faq_item>
        </dl>

        <section aria-labelledby="subscription-faq-heading" class="mt-20 md:mt-28" id="subscriptions">
          <h2 id="subscription-faq-heading" class="section-title mb-8">{~t"How subscriptions work"}</h2>
          <dl class="max-w-3xl">
            <.faq_item :for={{question, answer} <- subscription_questions()} question={question} heading="h3">
              {answer}
            </.faq_item>
          </dl>
        </section>
      </.container>
    </Layouts.app>
    """
  end

  @doc "Answered here and on a subscribable product's page."
  def subscription_questions do
    days = Edenflowers.Orders.Subscription.lead_days()

    [
      {~t"What will I get?",
       ~t"Whatever's looking best that week. I pick every bouquet myself, so no two are the same."},
      {~t"Can I pick it up instead?", pickup_answer()},
      {~t"When do I pay?",
       ~t"You pay for the first bouquet at checkout. After that, your card is charged #{days = days} days before each one, so I know to order your flowers."},
      {~t"Can I take a break or stop?",
       ~t"Yes, from your account, where you can also change the size, how often or the day. Make any change at least #{close = days + 1} days before a bouquet; after that, it's already on its way."},
      {~t"What if my card doesn't go through?",
       ~t"Your bouquet still comes, and I'll email you a link to pay for it. Your subscription waits until that's sorted."}
    ]
  end

  # Free-delivery products, subscriptions among them, get the free distance;
  # past it, the option's usual rate applies to the kilometres beyond.
  defp pickup_answer do
    case Edenflowers.Fulfillment.distance_priced_delivery() do
      %{free_dist_km: km, base_price: base, price_per_km: per_km} when km > 0 ->
        locale = Edenflowers.Format.locale()

        ~t"Of course. Choose delivery or pickup at checkout. The first #{km = km} km of delivery are free. Further out, it's #{base = Edenflowers.Format.currency(base, locale)} plus #{per_km = Edenflowers.Format.currency(per_km, locale)} for each km after that."

      _ ->
        ~t"Of course. Choose delivery or pickup at checkout."
    end
  end

  attr :question, :string, required: true
  attr :heading, :string, default: "h2", values: ["h2", "h3"]
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <div class="border-base-content/12 border-t py-8 last:border-b">
      <dt>
        <.dynamic_tag tag_name={@heading} class="font-serif text-balance mb-3.5 text-xl leading-snug md:text-2xl">
          {@question}
        </.dynamic_tag>
      </dt>
      <dd class="font-sans text-[1.0625rem] leading-[1.6] text-base-content max-w-[60ch]">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end
end
