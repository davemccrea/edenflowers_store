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
        <h1 class="font-sans mb-8 text-3xl font-semibold leading-tight tracking-tight sm:text-4xl md:mb-10">
          {~t"Privacy policy"}
        </h1>

        <p id="notice-updated" class="font-sans text-base-content/80 mb-16 max-w-3xl text-base leading-relaxed md:mb-20">
          {~t"Updated 26 October 2026."}
        </p>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <SectionIndex.section_index
            id="privacy-nav"
            sections={@sections}
            related_links={[
              {~q"/#{language}/faq", ~t"FAQ"},
              {~q"/#{language}/terms", ~t"Terms of sale"}
            ]}
          />

          <div class="space-y-16 md:space-y-20">
            <.privacy_section id="controller" title={~t"Who is responsible?"}>
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
                  {~t"We use names, email, phone and purchase details for orders, subscriptions, courses and enquiries. Checkout may create an account. Instagram handles are optional."}
                </li>
                <li>
                  {~t"Delivery details include recipient names, addresses, instructions, card messages and coordinates for calculating distance. Gift-recipient details come from the customer."}
                </li>
                <li>
                  {~t"We may photograph flowers left at the door as delivery evidence."}
                </li>
              </ul>
              <p>
                {~t"We cannot fulfil purchases without necessary contact and delivery details. Newsletter signup is optional."}
              </p>
              <p>{~t"Our legal bases are:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Purchases and purchase enquiries: our contract with you or steps you request before it."}
                </li>
                <li>{~t"Accounting records: our legal obligation."}</li>
                <li>
                  {~t"Our legitimate interests: fulfilling gifts, documenting delivery, administering purchases, handling complaints and preventing website abuse."}
                </li>
                <li>{~t"Newsletters require your consent."}</li>
              </ul>
            </.privacy_section>

            <.privacy_section id="sharing" title={~t"Where information is stored and who receives it"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Hetzner hosts our main customer database in Finland."}</li>
                <li>
                  {~t"Stripe handles payments and saved cards. We keep payment references and limited card details, not full card numbers or security codes."}
                </li>
                <li>
                  {~t"Brevo handles emails. For newsletter subscribers only, it also stores contact details, language and purchase statistics."}
                </li>
                <li>
                  {~t"Mapping services receive delivery addresses or coordinates. Website-security and mailbox providers handle traffic and emails."}
                </li>
                <li>{~t"Our accountant receives monthly purchase and payment records."}</li>
                <li>
                  {~t"Delivery photos may go to the purchaser, not necessarily the recipient. Emailed copies cannot be recalled."}
                </li>
              </ul>
            </.privacy_section>

            <.privacy_section id="cookies" title={~t"Cookies and fraud prevention"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Our session cookie keeps your cart, language and sign-in for up to 30 days."}</li>
                <li>
                  {~t"Stripe loads only on payment pages, for fraud prevention, and may use cookies and device/activity data there."}
                </li>
                <li>{~t"We do not use analytics or advertising cookies."}</li>
                <li>
                  {~t"Blocking cookies in your browser may stop the cart and sign-in working."}
                </li>
              </ul>
              <p>
                {~t"Browser settings do not replace required consent."}
              </p>
              <p>
                {~t"Our database stores error reports, which may include IP addresses, browser details and form data."}
              </p>
            </.privacy_section>

            <.privacy_section id="retention" title={~t"How long we keep information"}>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>
                  {~t"Accounting: generally at least six years for vouchers and business correspondence, from the end of the calendar year in which the financial year ended. Certain records require ten years from the financial-year end."}
                </li>
                <li>
                  {~t"Newsletters: until withdrawal or unsubscribe. Limited opt-out records prevent further marketing; consent evidence may remain where necessary."}
                </li>
                <li>{~t"Error reports: 90 days."}</li>
                <li>
                  {~t"Routine database backups: about 30 days."}
                </li>
              </ul>
              <p>
                {~t"Accounting retention does not automatically apply to delivery-only details."}
              </p>
            </.privacy_section>

            <.privacy_section id="rights" title={~t"Your rights"}>
              <p>{~t"Email #{email = Business.email()} to:"}</p>
              <ul class="list-disc space-y-3 pl-6 marker:text-base-content/50">
                <li>{~t"Request access to or correction of your data."}</li>
                <li>{~t"Request deletion, restriction or portability."}</li>
                <li>{~t"Object to legitimate-interest processing or direct marketing."}</li>
              </ul>
              <p>
                {~t"Requests are normally free. We may verify your identity. Within one month we respond or explain a lawful extension. Legal conditions apply; accounting records may need keeping."}
              </p>
              <p>
                {~t"Unsubscribe or contact us to withdraw newsletter consent anytime. Earlier lawful processing is unaffected."}
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
      <h2 id={"#{@id}-heading"} class="font-sans mb-6 text-xl font-semibold leading-snug md:text-2xl">{@title}</h2>
      <div class="font-sans text-base-content max-w-[60ch] space-y-6 text-base font-normal leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end
end
