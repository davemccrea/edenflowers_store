defmodule EdenflowersWeb.Marketing.FaqLive do
  @moduledoc """
  Answers to the questions customers ask Jennie most, grouped into sections.
  The page and its FAQPage structured data are built from the same answers.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Format
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Business
  alias EdenflowersWeb.FaqComponents
  alias EdenflowersWeb.SectionIndex

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    sections = sections()

    {:ok,
     assign(socket,
       page_title: ~t"Frequently Asked Questions",
       alternates: alternates("/#{language}/faq"),
       page_description:
         ~t"Answers about ordering, delivery, pickup, flower care, payment, subscriptions, weddings and courses at Eden Flowers in Vaasa.",
       sections: sections,
       delivery_quote: nil,
       json_ld: faq_page(sections)
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
        <h1 class="font-sans mb-16 text-3xl font-semibold leading-tight tracking-tight sm:text-4xl md:mb-20">
          {~t"Frequently Asked Questions"}
        </h1>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <%!-- Phones get no index: closed, the page is under three screens and its headings do the job. --%>
          <SectionIndex.section_index
            id="faq-nav"
            sections={Enum.map(@sections, fn {id, title, _questions} -> {id, title} end)}
            related_links={[
              {~q"/#{language}/terms", ~t"Terms of sale"},
              {~q"/#{language}/privacy", ~t"Privacy policy"}
            ]}
          />

          <div>
            <div id="faq-questions" class="space-y-16 md:space-y-20">
              <section
                :for={{id, title, questions} <- @sections}
                aria-labelledby={"#{id}-faq-heading"}
                class="scroll-mt-8"
                id={id}
              >
                <h2 id={"#{id}-faq-heading"} class="font-sans mb-6 text-xl font-semibold leading-snug md:text-2xl">
                  {title}
                </h2>
                <div class="max-w-3xl">
                  <FaqComponents.faq_item
                    :for={{{question, answer}, index} <- Enum.with_index(questions)}
                    id={"#{id}-question-#{index}"}
                    question={question}
                  >
                    <.answer_block :for={block <- answer} block={block} delivery_quote={@delivery_quote} />
                  </FaqComponents.faq_item>
                  <p :if={id == "subscriptions"} class="pt-4">
                    {~t"Your subscription is covered by our"}
                    <a class="link-underline-static-body" href={terms_path("subscriptions")}>
                      {~t"subscription terms"}
                    </a>.
                  </p>
                </div>
              </section>

              <section
                aria-labelledby="ask-heading"
                class="bg-cream text-cream-content flex max-w-3xl flex-col items-start gap-6 px-6 py-10 sm:px-10"
              >
                <h2 id="ask-heading" class="font-sans text-balance text-xl font-semibold leading-snug md:text-2xl">
                  {~t"Didn't find your answer?"}
                </h2>
                <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
                  <.button href={contact_path()} variant="primary">{~t"Send me a message"}</.button>
                  <a href={"tel:#{Business.phone()}"} class="link-underline-static-body whitespace-nowrap">
                    {Business.phone_display()}
                  </a>
                </div>
              </section>
            </div>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:delivery_quoted, quote}, socket) do
    {:noreply, assign(socket, delivery_quote: quote)}
  end

  # Answers share their text with the JSON-LD; only the page renders link markup.
  # Lists may be plain (opening hours, for example) or bulleted.
  defp sections do
    [
      {"delivery", ~t"Delivery and pickup",
       [
         {~t"Where and when do you deliver?", delivery_area_answer()},
         {~t"Do you deliver to the hospital?",
          [
            ~t"Yes, to the ward, if it allows flowers. Please check with the ward first, and put the patient's name and ward in the delivery instructions."
          ]},
         {~t"What if nobody's home?",
          [
            {:paragraph,
             [
               ~t"I leave the flowers at the door and email you a photo showing where I've left them. If you're sending a gift, you receive an email when it's delivered. Add any door code to the delivery instructions.",
               ~t"If I can't get in, the",
               {:link, ~t"delivery terms", terms_path("delivery")},
               ~t"explain what happens next."
             ]}
          ]},
         {~t"Where and when can I pick up my order?",
          [
            {:paragraph,
             [
               ~t"At Minimossen, #{address = Business.street_address()}, #{town = Business.postal_town()}. Choose your pickup date at checkout. I'll message you when your order is ready. Collect it during opening hours.",
               ~t"Please",
               {:link, ~t"get in touch", contact_path()},
               ~t"if you need another time."
             ]},
            {:list, Business.opening_hours_lines()}
          ]}
       ]},
      {"ordering", ~t"Ordering",
       [
         {~t"Can I order something that isn't in the online shop?",
          [
            {:paragraph,
             [
               ~t"Yes.",
               {:link, ~t"Tell me what you have in mind", contact_path()},
               ~t"and I'll make it to order."
             ]}
          ]},
         {~t"Can I add a card with a message?",
          [~t"Yes, if you're sending flowers as a gift. Choose a card at checkout and write your message."]},
         {~t"Can I cancel an order I made online?",
          [
            {:paragraph,
             [
               ~t"Yes, cancel",
               {:link, ~t"from your account", ~p"/account"},
               ~t"until #{days = Subscription.change_deadline_days()} days before delivery or pickup, for a full refund. After that,",
               {:link, ~t"get in touch", contact_path()},
               ~t"to discuss the options in the",
               {:link, ~t"cancellation terms.", terms_path("cancellation")}
             ]}
          ]}
       ]},
      {"care", ~t"Flowers and care",
       [
         {~t"How long will my flowers last, and how should I care for them?",
          [
            ~t"A lot depends on the flowers, but typically around 7–10 days.",
            {:bullets,
             [
               ~t"Use a clean vase with fresh water.",
               ~t"Remove any leaves that would sit below the waterline.",
               ~t"Check the water level regularly and top up as needed. Change the water and re-cut the stems every 2–3 days.",
               ~t"Keep the flowers in a cool spot, away from radiators, other heat sources and ripe fruit."
             ]}
          ]},
         {~t"Are your flowers local and seasonal?",
          [
            {:paragraph,
             [
               ~t"I use local and seasonal flowers whenever possible.",
               ~t"Any substitutions follow the",
               {:link, ~t"quality terms.", terms_path("quality")}
             ]}
          ]},
         {~t"What if my flowers arrive damaged or wilt early?",
          [
            {:paragraph,
             [
               {:link, ~t"Let me know", contact_path()},
               ~t"as soon as possible and send a photo.",
               ~t"I'll replace them or refund you, provided care instructions are followed.",
               ~t"Our",
               {:link, ~t"quality terms", terms_path("quality")},
               ~t"explain the conditions."
             ]}
          ]}
       ]},
      {"payment", ~t"Payment",
       [
         {~t"How can I pay?",
          [~t"MobilePay, card, Apple Pay or Google Pay. Subscriptions require a card. Prices include VAT."]},
         {~t"Can businesses pay by invoice?",
          [
            {:paragraph,
             [
               ~t"Yes. I also offer invoice payment for larger orders, such as weddings.",
               {:link, ~t"Get in touch", contact_path()},
               ~t"to arrange it."
             ]}
          ]}
       ]},
      {"subscriptions", ~t"Subscriptions", Enum.map(FaqComponents.subscription_questions(), fn {q, a} -> {q, [a]} end)},
      {"weddings", ~t"Weddings",
       [
         {~t"How far ahead should I book wedding flowers?",
          [
            {:paragraph,
             [
               ~t"Saturdays in particular fill up quickly, as I can only take on a limited number of weddings each Saturday. Most couples book 9–12 months ahead.",
               ~t"Please",
               {:link, ~t"get in touch", contact_path()},
               ~t"well in advance."
             ]}
          ]},
         {~t"Do you provide wedding flowers outside Vaasa?", [~t"Yes, gladly. Travel is quoted separately."]},
         {~t"How does payment for a wedding work?",
          [
            {:paragraph,
             [
               ~t"Half is invoiced as a booking fee about 4 weeks before the wedding, the rest afterwards.",
               ~t"Your booking follows the",
               {:link, ~t"wedding terms.", terms_path("weddings")}
             ]}
          ]}
       ]},
      {"courses", ~t"Courses",
       [
         {~t"How do I cancel a course booking?",
          [
            ~t"Reply to your confirmation email. Each course page lists the deadline for a full refund and the cancellation fee after that."
          ]},
         {~t"Can I book a private course for my group?",
          [
            {:paragraph,
             [
               ~t"Yes, I offer",
               {:link, ~t"courses for private groups", ~q"/#{language}/courses" <> "#groups"},
               ~t"at Minimossen or at your own premises."
             ]}
          ]}
       ]}
    ]
  end

  defp terms_path(section), do: ~q"/#{language}/terms" <> "##{section}"
  defp contact_path, do: ~q"/#{language}/contact"

  defp delivery_area_answer do
    locale = Format.locale()

    option = Edenflowers.Fulfillment.distance_priced_delivery()

    area =
      case option do
        %{max_dist_km: max, base_price: base, price_per_km: per_km} when is_integer(max) ->
          ~t"Within #{km = max} km driving distance of the shop, for #{base = Format.currency(base, locale)} plus #{per_km = Format.currency(per_km, locale)} per km."

        _ ->
          ~t"Enter the address at checkout to see whether I deliver there and what it costs."
      end

    free =
      if km = Edenflowers.Fulfillment.free_dist_km(),
        do: ~t"Some products, like subscriptions, are delivered free within #{km = km} km."

    availability =
      ~t"Checkout shows the available delivery and pickup dates for the products you choose. The usual cutoff for same-day orders is midday."

    pricing = {:paragraph, Enum.reject([area, free], &is_nil/1)}
    checker_intro = if option, do: ~t"Enter an address below to check the delivery distance and price."
    checker = if option, do: {:delivery_checker, option}

    Enum.reject([pricing, checker_intro, checker, availability, ~t"There are no set delivery times."], &is_nil/1)
  end

  defp faq_page(sections) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        for {_id, _title, questions} <- sections, {question, answer} <- questions do
          %{
            "@type" => "Question",
            "name" => question,
            "acceptedAnswer" => %{"@type" => "Answer", "text" => plain_text(answer)}
          }
        end
    }
  end

  defp plain_text(answer) do
    answer
    |> Enum.flat_map(fn
      {:delivery_checker, _option} ->
        []

      {:paragraph, parts} ->
        [
          Enum.map_join(parts, " ", fn
            {:link, text, _path} -> text
            text -> text
          end)
        ]

      {:list, lines} ->
        Enum.map(lines, &(&1 <> "."))

      {:bullets, lines} ->
        lines

      paragraph ->
        [paragraph]
    end)
    |> Enum.join(" ")
  end

  defp answer_block(%{block: {kind, lines}} = assigns) when kind in [:list, :bullets] do
    assigns = assign(assigns, lines: lines, bullets?: kind == :bullets)

    ~H"""
    <ul class={@bullets? && "list-disc space-y-2 pl-5"}>
      <li :for={line <- @lines}>{line}</li>
    </ul>
    """
  end

  defp answer_block(%{block: {:paragraph, parts}} = assigns) do
    assigns = assign(assigns, parts: parts)

    ~H"""
    <p>
      <%= for part <- @parts do %>
        <.answer_part part={part} />{" "}
      <% end %>
    </p>
    """
  end

  defp answer_block(%{block: {:delivery_checker, option}} = assigns) do
    assigns = assign(assigns, option: option)

    ~H"""
    <div class="space-y-4 pt-2">
      <form id="faq-delivery-cost" phx-submit="lookup_address" phx-target="#address-input">
        <.live_component
          module={EdenflowersWeb.Checkout.AddressInput}
          id="address-input"
          address=""
          fulfillment_option={@option}
          quote={@delivery_quote}
          label={~t"Check delivery distance and price"}
          autocomplete="street-address"
          show_confirmation={false}
          show_label={false}
          required={false}
        />
      </form>
      <div aria-live="polite" aria-atomic="true" data-testid="faq-delivery-quote">
        <p :if={@delivery_quote} class="text-success font-semibold">
          {~t"Delivery: #{price = Format.currency(@delivery_quote.fulfillment_fee, Format.locale())}"}
        </p>
      </div>
    </div>
    """
  end

  defp answer_block(assigns) do
    ~H"""
    <p>{@block}</p>
    """
  end

  defp answer_part(%{part: {:link, text, path}} = assigns) do
    assigns = assign(assigns, text: text, path: path)

    ~H"""
    <a class="link-underline-static-body" href={@path}>{@text}</a>
    """
  end

  defp answer_part(assigns) do
    ~H"""
    {@part}
    """
  end
end
