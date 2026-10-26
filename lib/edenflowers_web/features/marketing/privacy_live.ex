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
          {~t"Last updated 26 October 2026. This notice is still a draft: retention, overseas safeguards, cookie requirements and gift-recipient information remain under review."}
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
                  {~t"We use contact and purchase details for orders, subscriptions, courses and enquiries. Checkout can create a customer account without separate registration. Custom orders may include an optional Instagram handle."}
                </li>
                <li>
                  {~t"Delivery details include recipients, addresses, instructions and card messages, plus the coordinates we look up to calculate delivery distance. Gift-recipient details come from the customer."}
                </li>
                <li>
                  {~t"We may photograph flowers left at the door to show where they were delivered."}
                </li>
              </ul>
              <p>
                {~t"Without necessary contact and delivery details, we cannot complete your purchase. Newsletter signup is optional."}
              </p>
              <p>{~t"Our legal bases are:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Purchases, subscriptions, course bookings and purchase enquiries: the contract with you or steps taken at your request before it."}
                </li>
                <li>{~t"Accounting records: our legal obligation."}</li>
                <li>
                  {~t"Gift deliveries, delivery evidence and customer administration: our legitimate interests in fulfilling gifts and handling purchases and complaints. Website security: our legitimate interest in preventing abuse."}
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
                  {~t"Brevo handles emails and contacts, including non-subscribers with phone numbers. It receives contact details, language, order count, latest order date and total spent. Only subscribers receive newsletters."}
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
                  {~t"Delivery photographs may be emailed to the purchasing customer, who may not be the recipient. Copies in the customer's inbox cannot be recalled."}
                </li>
              </ul>
              <p>
                {~t"We are confirming which services process data outside the EEA, the applicable safeguards and how to obtain a copy of them."}
              </p>
            </.privacy_section>

            <.privacy_section id="cookies" title={~t"Cookies and fraud prevention"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Our session cookie remembers your cart, language and sign-in for up to 30 days."}</li>
                <li>{~t"Stripe loads site-wide for fraud prevention and may use cookies, device and activity data."}</li>
                <li>{~t"We do not use analytics or advertising cookies."}</li>
                <li>
                  {~t"You can block or delete cookies in your browser settings, though the cart and sign-in will stop working."}
                </li>
              </ul>
              <p>
                {~t"Stripe's cookie and device-access consent requirements are still being assessed. Browser settings do not replace consent where it is required."}
              </p>
              <p>
                {~t"Error reports are stored in our own database and may contain IP addresses, browser information and submitted form data."}
              </p>
            </.privacy_section>

            <.privacy_section id="retention" title={~t"How long we keep information"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Accounting records: vouchers and business correspondence must generally be kept for at least six years from the end of the calendar year in which the financial year ended. Certain accounting records require ten years from the financial-year end. We are confirming the categories with our accountant."}
                </li>
                <li>
                  {~t"Customer, subscription and enquiry records: expiry rules are being confirmed. These records, abandoned checkouts and change histories are not yet routinely deleted."}
                </li>
                <li>
                  {~t"Newsletters: until you unsubscribe or withdraw consent. Limited suppression records prevent further marketing; consent evidence may also be retained where necessary."}
                </li>
                <li>{~t"Error reports: 90 days."}</li>
                <li>
                  {~t"Backups: routine database backups rotate after about 30 days. Other copies are being reviewed."}
                </li>
                <li>
                  {~t"Delivery photographs: intended retention is two weeks. Routine deletion is not yet implemented."}
                </li>
              </ul>
              <p>
                {~t"Accounting duties do not automatically require us to retain delivery-only details for the same period."}
              </p>
            </.privacy_section>

            <.privacy_section id="rights" title={~t"Your rights"}>
              <p>{~t"Email #{email = Business.email()} to:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Request access to your personal data or correction of incorrect details."}</li>
                <li>{~t"Request deletion, restriction of processing or portability of your data."}</li>
                <li>{~t"Object to legitimate-interest processing or direct marketing."}</li>
              </ul>
              <p>
                {~t"Rights depend on legal conditions. Requests are normally free. We may need to verify your identity. We respond within one month or explain any lawful extension within that month. Accounting obligations may prevent deletion of some records."}
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
