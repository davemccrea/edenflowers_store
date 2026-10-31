defmodule EdenflowersWeb.Marketing.TermsLive do
  @moduledoc """
  The shop's terms of sale, with general purchase terms followed by service-specific terms.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business
  alias EdenflowersWeb.SectionIndex

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: ~t"Terms of sale",
       alternates: alternates("/#{language}/terms"),
       page_description: ~t"Eden Flowers' terms for payment, delivery and pickup, cancellation, quality and invoices.",
       sections: [
         {"payment", ~t"Prices and payment"},
         {"delivery", ~t"Delivery and pickup"},
         {"quality", ~t"Quality"},
         {"cancellation", ~t"Changes and cancellations"},
         {"subscriptions", ~t"Subscriptions"},
         {"weddings", ~t"Weddings"},
         {"courses", ~t"Courses"},
         {"seller", ~t"Seller and contact details"}
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
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <.container>
        <h1 class="font-sans mb-8 text-3xl font-semibold leading-tight tracking-tight sm:text-4xl md:mb-10">
          {~t"Terms of sale"}
        </h1>

        <p id="notice-updated" class="font-sans text-base-content/80 mb-16 max-w-3xl text-base leading-relaxed md:mb-20">
          {~t"Updated 26 October 2026."}
        </p>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <SectionIndex.section_index
            id="terms-nav"
            sections={@sections}
            related_links={[
              {~q"/#{language}/faq", ~t"FAQ"},
              {~q"/#{language}/privacy", ~t"Privacy policy"}
            ]}
          />

          <div class="space-y-16 md:space-y-20">
            <.terms_section id="payment" title={~t"Prices and payment"}>
              <.terms_subsection id="checkout-payments" title={~t"Checkout payments"}>
                <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                  <li>
                    {~t"Prices include VAT. At checkout you can pay with MobilePay, card, Apple Pay or Google Pay. Subscriptions require a card."}
                  </li>
                  <li>
                    {~t"All payments on this website are processed by Stripe."}
                    <a class="link-underline-static-body" href={~q"/#{language}/privacy" <> "#sharing"}>
                      {~t"Privacy policy"}
                    </a>
                  </li>
                </ul>
              </.terms_subsection>
              <.terms_subsection id="invoices" title={~t"Invoices"}>
                <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                  <li>
                    {~t"I offer invoices to businesses and for larger orders such as weddings. Payment is due as stated on the invoice."}
                  </li>
                  <li>
                    {~t"Late payment adds interest under the Interest Act, plus #{fee = Edenflowers.Format.storefront_price(5, Edenflowers.Format.locale())} for each reminder."}
                  </li>
                </ul>
              </.terms_subsection>
            </.terms_section>

            <.terms_section id="delivery" title={~t"Delivery and pickup"}>
              <.terms_subsection id="delivery-area" title={~t"Delivery area and timing"}>
                <p>{delivery_area()}</p>
              </.terms_subsection>
              <.terms_subsection id="pickup" title={~t"Pickup"}>
                <p>
                  {~t"Collect your order during opening hours, unless we've agreed on another time."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="unattended-delivery" title={~t"If nobody is home"}>
                <p>
                  {~t"If nobody's home, I'll leave the flowers at the door and email you a photo showing where I've left them."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="delivery-problems" title={~t"Access problems or incorrect details"}>
                <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                  <li>
                    {~t"If I can't reach the door, for example a locked stairwell, your order goes back to the shop for you to pick up, or you can pay for another delivery. Add any door code to the delivery instructions."}
                  </li>
                  <li>{~t"If the address or recipient details given at checkout are wrong, I can't refund the order."}</li>
                </ul>
              </.terms_subsection>
            </.terms_section>

            <.terms_section id="quality" title={~t"Quality"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"If a flower is out of season or unavailable, I use something similar of the same value."}
                </li>
                <li>
                  <.quality_contact />
                  {~t"I'll replace them or refund you, provided care instructions are followed."}
                </li>
              </ul>
              <p>
                <a class="link-underline-static-body" href={~q"/#{language}/faq" <> "#care"}>
                  {~t"Read the care instructions"}
                </a>
              </p>
            </.terms_section>

            <.terms_section id="cancellation" title={~t"Changes and cancellations"}>
              <.terms_subsection id="online-orders" title={~t"Online flower orders"}>
                <p>
                  {~t"You can cancel or change an online order from your account until #{days = Edenflowers.Orders.Subscription.change_deadline_days()} days before delivery or pickup, for a full refund."}
                  <a class="link-underline-static-body" href={~q"/#{language}/contact"}>
                    {~t"Get in touch after that."}
                  </a>
                </p>
                <p>
                  <a class="link-underline-static-body" href={~p"/account"}>{~t"Go to your account"}</a>
                </p>
              </.terms_subsection>
              <.terms_subsection id="withdrawal" title={~t"Right of withdrawal"}>
                <p>
                  {~t"Flowers are made to order and perishable, so the 14-day right of withdrawal doesn't apply."}
                </p>
              </.terms_subsection>
              <p>
                {~t"Wedding and course bookings have separate cancellation terms:"}
                <a class="link-underline-static-body" href="#weddings">{~t"Weddings"}</a>, <a
                  class="link-underline-static-body"
                  href="#courses"
                >{~t"Courses"}</a>.
              </p>
            </.terms_section>

            <.terms_section id="subscriptions" title={~t"Subscriptions"}>
              <.terms_subsection id="subscription-billing" title={~t"Billing"}>
                <p>
                  {~t"You pay for the first bouquet at checkout. After that, your saved card is charged #{days = Edenflowers.Orders.Subscription.lead_days()} days before each delivery or pickup."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="failed-payments" title={~t"Failed payments"}>
                <p>
                  {~t"If a charge doesn't go through, the bouquet still comes and I'll get in touch with payment instructions."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="subscription-changes" title={~t"Changing or stopping a subscription"}>
                <p>
                  {~t"You can pause, cancel or change your subscription from your account. Make changes at least #{close = Edenflowers.Orders.Subscription.change_deadline_days()} days before delivery or pickup. Cancelling after that stops future bouquets, but the booked bouquet still comes."}
                </p>
                <p>
                  <a class="link-underline-static-body" href={~p"/account"}>{~t"Go to your account"}</a>
                </p>
              </.terms_subsection>
            </.terms_section>

            <.terms_section id="weddings" title={~t"Weddings"}>
              <.terms_subsection id="wedding-pricing" title={~t"Pricing and delivery"}>
                <p>
                  {~t"For weddings, final prices depend on the flowers and technique you choose. Delivery costs are added for deliveries outside Vaasa."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="wedding-payment" title={~t"Payment schedule"}>
                <p>
                  {~t"Half is invoiced as a booking fee about 4 weeks before the wedding, the rest afterwards."}
                </p>
              </.terms_subsection>
              <.terms_subsection id="wedding-cancellation" title={~t"Cancellation and booking fee"}>
                <p>
                  {~t"The first instalment is a booking fee and is not refunded if you cancel later than four weeks before the wedding."}
                </p>
              </.terms_subsection>
            </.terms_section>

            <.terms_section id="courses" title={~t"Courses"}>
              <p>{~t"For courses, the cancellation terms on each course's page apply."}</p>
              <p>
                <a class="link-underline-static-body" href={~q"/#{language}/courses"}>{~t"See the courses"}</a>
              </p>
            </.terms_section>

            <.terms_section id="seller" title={~t"Seller and contact details"}>
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
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp quality_contact(assigns) do
    message =
      ~t"If your flowers arrive damaged or wilt early, #{contact = "__CONTACT_LINK__"} as soon as possible and send a photo."

    # Keep the sentence translatable as a whole without putting HTML in translations.
    [before_link, after_link] = String.split(message, "__CONTACT_LINK__", parts: 2)
    assigns = assign(assigns, before_link: before_link, after_link: after_link)

    ~H"""
    {@before_link}<a class="link-underline-static-body" href={~q"/#{language}/contact"}>{~t"let me know"}</a>{@after_link}
    """
  end

  defp delivery_area do
    case Edenflowers.Fulfillment.distance_priced_delivery() do
      %{max_dist_km: km} when is_integer(km) ->
        ~t"I deliver within #{km = km} km driving distance of the shop, on the day you choose at checkout. There are no set delivery times."

      _ ->
        ~t"I deliver on the day you choose at checkout. There are no set delivery times."
    end
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp terms_section(assigns) do
    ~H"""
    <section aria-labelledby={@id} class="max-w-3xl">
      <h2 id={@id} class="font-sans mb-6 text-xl font-semibold leading-snug md:text-2xl">{@title}</h2>
      <div class="font-sans text-base-content max-w-[60ch] space-y-6 text-base font-normal leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp terms_subsection(assigns) do
    ~H"""
    <section aria-labelledby={@id}>
      <h3 id={@id} class="text-base-content font-sans mb-2 text-base font-semibold leading-snug">{@title}</h3>
      <div class="space-y-3">{render_slot(@inner_block)}</div>
    </section>
    """
  end
end
