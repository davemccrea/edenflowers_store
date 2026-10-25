defmodule EdenflowersWeb.Marketing.TermsLive do
  @moduledoc """
  The shop's terms of sale: delivery, substitution, cancellation, quality and invoices.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: ~t"Terms of sale",
       alternates: alternates("/#{language}/terms"),
       page_description:
         ~t"Eden Flowers' terms for payment, delivery and pickup, substitutions, cancellation, quality and invoices.",
       sections: [
         {"seller", ~t"Seller"},
         {"payment", ~t"Prices and payment"},
         {"delivery", ~t"Delivery and pickup"},
         {"substitution", ~t"Substitutions"},
         {"cancellation", ~t"Cancellation"},
         {"quality", ~t"Quality"},
         {"invoices", ~t"Invoices"}
       ]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <.container>
        <h1 class="page-title mb-16 md:mb-20">
          {~t"Terms of sale"}
        </h1>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <nav aria-labelledby="terms-nav-heading" class="mb-16 md:sticky md:top-8 md:mb-0 md:self-start">
            <h2 id="terms-nav-heading" class="text-base-content/75 mb-3 text-sm">{~t"On this page"}</h2>
            <ul class="flex flex-wrap gap-x-6 gap-y-2 md:flex-col md:gap-3">
              <li :for={{id, title} <- @sections}>
                <a href={"##{id}"} class="link-underline-hover">{title}</a>
              </li>
            </ul>
          </nav>

          <div class="space-y-16 md:space-y-20">
            <.terms_section id="seller" title={~t"Seller"}>
              <p>
                Eden Flowers<br />
                {~t"Business ID:"} {Business.business_id()}<br />
                {Business.registered_address()}
              </p>
              <p>
                <a class="link-underline-static-body" href={"mailto:#{Business.email()}"}>{Business.email()}</a><br />
                <a class="link-underline-static-body" href={"tel:#{Business.phone()}"}>{Business.phone_display()}</a>
              </p>
            </.terms_section>

            <.terms_section id="payment" title={~t"Prices and payment"}>
              <p>{~t"Prices include VAT. At checkout you can pay with MobilePay, card, Apple Pay or Google Pay."}</p>
              <p>
                {~t"A subscription is charged to the card you saved when you set it up, #{days = Edenflowers.Orders.Subscription.lead_days()} days before each bouquet."}
              </p>
              <p>
                {~t"If a charge doesn't go through, the bouquet still comes and I'll email you a payment link. Nothing more is sent or charged until it's paid or you add a new card."}
              </p>
            </.terms_section>

            <.terms_section id="delivery" title={~t"Delivery and pickup"}>
              <p>{delivery_area()}</p>
              <p>
                {~t"For pickup, choose a date at checkout and I'll send you a message when your order is ready. Collect it during opening hours, or get in touch and we'll find another time."}
              </p>
              <p>{~t"If nobody's home, I'll leave the flowers at the door and email you a photo of where they are."}</p>
              <p>
                {~t"If I can't reach the door, for example a locked stairwell, your order goes back to the shop for you to pick up, or you can pay for another delivery. Add any door code to the delivery instructions."}
              </p>
              <p>{~t"If the address or recipient details given at checkout are wrong, I can't refund the order."}</p>
            </.terms_section>

            <.terms_section id="substitution" title={~t"Substitutions"}>
              <p>
                {~t"If a flower is out of season or the wholesalers don't have it, I may replace it with something similar of the same value."}
              </p>
            </.terms_section>

            <.terms_section id="cancellation" title={~t"Cancellation"}>
              <p>
                {~t"You can cancel or change an online order from your account until #{days = Edenflowers.Orders.Subscription.change_deadline_days()} days before delivery or pickup, for a full refund. After that, get in touch with me."}
              </p>
              <p>{~t"For courses, the cancellation terms on each course's page apply."}</p>
              <p>
                {~t"For weddings, half is invoiced as a booking fee about 4 weeks before the wedding. Once invoiced, the booking fee isn't refunded if you cancel."}
              </p>
              <p>
                {~t"Flowers are made to order and perishable, so the 14-day right of withdrawal doesn't apply."}
              </p>
            </.terms_section>

            <.terms_section id="quality" title={~t"Quality"}>
              <p>
                {~t"If your flowers arrive damaged or wilt early, send me a photo within 4 days of delivery and I'll replace them or refund you. This applies as long as they've been kept in fresh water."}
              </p>
            </.terms_section>

            <.terms_section id="invoices" title={~t"Invoices"}>
              <p>
                {~t"I offer invoices to businesses and for larger orders such as weddings. Payment is due as stated on the invoice."}
              </p>
              <p>
                {~t"Late payment adds interest under the Interest Act, plus #{fee = Edenflowers.Format.storefront_price(5, Edenflowers.Format.locale())} for each reminder."}
              </p>
            </.terms_section>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp delivery_area do
    case Edenflowers.Fulfillment.distance_priced_delivery() do
      %{max_dist_km: km} when is_integer(km) ->
        ~t"I deliver within #{km = km} km of the shop, on the day you choose at checkout. There are no set delivery times."

      _ ->
        ~t"I deliver on the day you choose at checkout. There are no set delivery times."
    end
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp terms_section(assigns) do
    ~H"""
    <section aria-labelledby={"#{@id}-heading"} class="scroll-mt-8" id={@id}>
      <h2 id={"#{@id}-heading"} class="section-title mb-8">{@title}</h2>
      <div class="font-sans text-[1.0625rem] leading-[1.6] text-base-content max-w-[60ch] space-y-4">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
