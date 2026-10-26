defmodule EdenflowersWeb.Marketing.PrivacyLive do
  @moduledoc """
  How Eden Flowers handles personal data.
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
       page_description: ~t"How Eden Flowers handles personal data.",
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
        <h1 class="page-title mb-8 md:mb-10">{~t"Privacy policy"}</h1>

        <p id="notice-status" class="font-sans text-base-content/80 mb-16 max-w-3xl text-base leading-relaxed md:mb-20">
          {~t"Last updated 26 October 2026. This notice is still a draft: our retention periods and the safeguards for processing outside the EEA are being confirmed."}
        </p>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <SectionIndex.section_index id="privacy-nav" sections={@sections} />

          <div class="space-y-16 md:space-y-20">
            <.privacy_section id="controller" title={~t"Who is responsible?"}>
              <p>{~t"Eden Flowers is responsible for the personal data described here."}</p>
              <p>
                {~t"Jennie McCrea, trading as Eden Flowers"}<br />
                {~t"Business ID:"} {Business.business_id()}<br />
                {~t"Registered address:"} {Business.registered_address()}, {~t"Finland"}
              </p>
              <p>
                <a class="link-underline-static-body" href={"mailto:#{Business.email()}"}>{Business.email()}</a><br />
                <a class="link-underline-static-body" href={"tel:#{Business.phone()}"}>{Business.phone_display()}</a>
              </p>
            </.privacy_section>

            <.privacy_section id="information" title={~t"What information we use and why"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"We use your name, email, phone number and purchase details to handle orders, subscriptions, courses and enquiries. For custom orders we may also collect your Instagram handle."}
                </li>
                <li>
                  {~t"Delivery details include recipients, addresses, instructions and card messages, plus the coordinates we look up to calculate delivery distance. Gift-recipient details come from the customer."}
                </li>
                <li>
                  {~t"We may photograph flowers left at the door to show where they were delivered."}
                </li>
              </ul>
              <p>{~t"Required details are necessary to fulfil purchases."}</p>
              <p>{~t"We use your data only where the law recognises a reason:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Purchases and enquiries about a purchase rely on the contract with you or the steps taken before it."}
                </li>
                <li>{~t"The law requires us to keep accounting records."}</li>
                <li>
                  {~t"Recipient deliveries, customer administration and website security rely on our legitimate interests."}
                </li>
                <li>{~t"Newsletters require your consent."}</li>
              </ul>
            </.privacy_section>

            <.privacy_section id="sharing" title={~t"Where information is stored and who receives it"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Our main customer database is hosted by Hetzner in Finland."}</li>
                <li>
                  {~t"Stripe handles payments and saved cards. We store payment references and limited card details, such as the brand and last four digits, not full card numbers or security codes."}
                </li>
                <li>
                  {~t"Brevo handles emails and customer contacts, including non-subscribers. It receives contact details, language, order count, latest order date and total spent. Only subscribers receive newsletters."}
                </li>
                <li>{~t"HERE checks delivery addresses and calculates distances."}</li>
                <li>{~t"Mapbox displays delivery maps."}</li>
                <li>{~t"Opening directions shares the destination with Google Maps."}</li>
                <li>{~t"Cloudflare handles website traffic and security."}</li>
                <li>{~t"Our accountant receives purchase and payment records each month."}</li>
                <li>
                  {~t"Our email provider hosts the #{email = Business.email()} mailbox, where enquiries and order emails arrive."}
                </li>
                <li>
                  {~t"Delivery photographs are emailed to the recipient, so a copy stays in their inbox and cannot be recalled."}
                </li>
              </ul>
              <p>
                {~t"Some of these services are based outside the EEA. We are confirming which safeguards apply to that processing and will describe them here before this notice is final."}
              </p>
            </.privacy_section>

            <.privacy_section id="cookies" title={~t"Cookies and fraud prevention"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Our session cookie remembers your cart, language and sign-in for 30 days."}</li>
                <li>{~t"Stripe loads site-wide for fraud prevention and may use cookies, device and activity data."}</li>
                <li>{~t"We do not use analytics or advertising cookies."}</li>
                <li>
                  {~t"You can block or delete cookies in your browser settings, though the cart and sign-in will stop working."}
                </li>
              </ul>
              <p>
                {~t"Error reports are stored in our own database and may contain IP addresses, browser information and submitted form data."}
              </p>
            </.privacy_section>

            <.privacy_section id="retention" title={~t"How long we keep information"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Orders and payment records: six years from the end of the financial year in which you bought, because the law requires us to keep accounting records. Some records must be kept for ten years; our accountant decides which."}
                </li>
                <li>
                  {~t"Customer and subscription details: while your account or subscription is open, and while a purchase is still within its accounting period."}
                </li>
                <li>{~t"Enquiries: twelve months after we last hear from you."}</li>
                <li>
                  {~t"Newsletter consent: until you unsubscribe. We keep the unsubscribe record so that we do not email you again."}
                </li>
                <li>{~t"Error reports: 90 days."}</li>
                <li>{~t"Backups: 30 days."}</li>
                <li>
                  {~t"Delivery photographs: two weeks. Automatic deletion is not yet in place; until it is, ask us and we will delete the photograph."}
                </li>
              </ul>
            </.privacy_section>

            <.privacy_section id="rights" title={~t"Your rights"}>
              <p>{~t"Email #{email = Business.email()} to:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Request access to your personal data or correction of incorrect details."}</li>
                <li>{~t"Request deletion, restriction of processing or portability of your data."}</li>
                <li>{~t"Object to legitimate-interest processing or direct marketing."}</li>
              </ul>
              <p>
                {~t"Rights depend on legal conditions. We may need to verify your identity. We normally respond within one month; legal obligations may prevent deletion."}
              </p>
              <p>
                {~t"Unsubscribe anytime or withdraw newsletter consent by contacting us. Withdrawal does not affect earlier lawful processing."}
              </p>
              <p>
                {~t"You can complain to Finland's"}
                <a class="link-underline-static-body" href="https://tietosuoja.fi/en">
                  {~t"Office of the Data Protection Ombudsman"}
                </a>.
              </p>
              <p>
                {~t"Read also our"}
                <.link class="link-underline-static-body" navigate={~q"/#{language}/terms"}>
                  {~t"terms of sale"}
                </.link>.
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
