defmodule EdenflowersWeb.Marketing.PrivacyLive do
  @moduledoc """
  The privacy-policy draft, with unresolved publication details explicitly marked.
  """

  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Business
  alias EdenflowersWeb.SectionIndex

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: ~t"Privacy policy",
       page_description: ~t"Draft information about how Eden Flowers handles personal data.",
       page_robots: "noindex",
       alternates: alternates("/#{language}/privacy"),
       sections: [
         {"controller", ~t"Who is responsible?"},
         {"information", ~t"What information we use and why"},
         {"sharing", ~t"Where information is stored and who receives it"},
         {"cookies", ~t"Cookies and fraud prevention"},
         {"retention", ~t"How long we keep information"},
         {"rights", ~t"Your rights"}
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
        <h1 class="page-title mb-8">{~t"Privacy policy"}</h1>

        <aside
          id="privacy-draft"
          aria-labelledby="privacy-draft-heading"
          class="mb-16 max-w-3xl rounded border p-6 md:mb-20"
        >
          <h2 id="privacy-draft-heading" class="font-sans mb-2 font-medium">
            {~t"Draft — not a completed privacy notice"}
          </h2>
          <p class="text-base-content/80 font-sans leading-relaxed">
            {~t"Other retention periods, overseas processing and remaining providers need confirmation."}
          </p>
        </aside>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <SectionIndex.section_index id="privacy-nav" sections={@sections} />

          <div class="space-y-16 md:space-y-20">
            <.privacy_section id="controller" title={~t"Who is responsible?"}>
              <p>
                {~t"Jennie McCrea, trading as Eden Flowers"}<br />
                {~t"Business ID:"} {Business.business_id()}<br />
                {~t"Registered address:"} {Business.registered_address()}
              </p>
              <p>
                <a class="link-underline-static-body" href={"mailto:#{Business.email()}"}>{Business.email()}</a><br />
                <a class="link-underline-static-body" href={"tel:#{Business.phone()}"}>{Business.phone_display()}</a>
              </p>
            </.privacy_section>

            <.privacy_section id="information" title={~t"What information we use and why"}>
              <p>
                {~t"We use your name, email, phone number and purchase details to handle orders, subscriptions, courses and enquiries. Delivery details include recipients, addresses, instructions and card messages. We may photograph flowers left at the door to show where they were delivered. Gift-recipient details come from the customer."}
              </p>
              <p>
                {~t"Purchases and pre-purchase enquiries rely on contracts or steps towards one; accounting relies on legal obligations. Recipient deliveries, customer administration and website security rely on our legitimate interests. Required details are necessary to fulfil purchases."}
              </p>
              <p>{~t"Newsletters require your consent."}</p>
            </.privacy_section>

            <.privacy_section id="sharing" title={~t"Where information is stored and who receives it"}>
              <p>{~t"Our main customer database is hosted by Hetzner in Finland."}</p>
              <p>
                {~t"Stripe handles payments and saved cards. We store payment references and limited card details, such as the brand and last four digits, not full card numbers or security codes."}
              </p>
              <p>
                {~t"Brevo handles emails and customer contacts, including non-subscribers. It receives contact details, language, order count, latest order date and total spent. Only subscribers receive newsletters."}
              </p>
              <p>
                {~t"HERE checks delivery addresses and calculates distances. Mapbox displays delivery maps; opening directions shares the destination with Google Maps. Cloudflare handles website traffic and security."}
              </p>
              <p data-draft-detail="recipients" class="border-l-2 pl-4">
                {~t"To confirm: other payment, accounting, delivery and email providers."}
              </p>
              <p data-draft-detail="transfers" class="border-l-2 pl-4">
                {~t"To confirm: processing outside the EEA, transfer safeguards and how to obtain them."}
              </p>
            </.privacy_section>

            <.privacy_section id="cookies" title={~t"Cookies and fraud prevention"}>
              <p>
                {~t"Our session cookie remembers your cart, language and sign-in for 30 days. Stripe loads site-wide for fraud prevention and may use cookies, device and activity data. Error reports may contain IP addresses, browser information and submitted data."}
              </p>
              <p data-draft-detail="fraud-checks" class="border-l-2 pl-4">
                {~t"To confirm: cookie consent and disclosures for automated fraud decisions."}
              </p>
            </.privacy_section>

            <.privacy_section id="retention" title={~t"How long we keep information"}>
              <p>{~t"The agreed retention period for delivery photographs is two weeks."}</p>
              <p data-draft-detail="photo-cleanup" class="border-l-2 pl-4">
                {~t"To implement: automatic deletion of delivery photographs."}
              </p>
              <p data-draft-detail="retention" class="border-l-2 pl-4">
                {~t"To confirm: retention periods for purchases, customer records, enquiries, other delivery details, newsletters and technical data."}
              </p>
            </.privacy_section>

            <.privacy_section id="rights" title={~t"Your rights"}>
              <p>
                {~t"Email #{email = Business.email()} to request access, correction, deletion, restriction or portability, or to object to legitimate-interest processing or direct marketing. Rights depend on legal conditions. We may need to verify your identity. We normally respond within one month; legal obligations may prevent deletion."}
              </p>
              <p>
                {~t"Unsubscribe anytime or withdraw newsletter consent by contacting us. Withdrawal does not affect earlier lawful processing."}
              </p>
              <p>
                {~t"You can complain to Finland's"}
                <a class="link-underline-static-body" href="https://tietosuoja.fi/en">
                  {~t"Office of the Data Protection Ombudsman"}
                </a>
              </p>
            </.privacy_section>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp privacy_section(assigns) do
    ~H"""
    <section aria-labelledby={"#{@id}-heading"} class="max-w-3xl scroll-mt-8" id={@id}>
      <h2 id={"#{@id}-heading"} class="section-title mb-6">{@title}</h2>
      <div class="font-sans text-base-content/80 max-w-[60ch] space-y-6 text-base font-normal leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
