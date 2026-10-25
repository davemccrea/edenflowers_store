defmodule EdenflowersWeb.Marketing.FaqLive do
  @moduledoc """
  Answers to the questions customers ask Jennie most, grouped into sections.
  The page and its FAQPage structured data are built from the same answers.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog.ProductVariantSize
  alias Edenflowers.Format
  alias Edenflowers.Orders.Subscription
  alias EdenflowersWeb.Business
  alias EdenflowersWeb.Marketing.ContactDrawer

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
      alternates={@alternates}
    >
      <.container>
        <h1 class="page-title mb-16 md:mb-20">
          {~t"Frequently Asked Questions"}
        </h1>

        <div class="md:grid-cols-[11rem_minmax(0,1fr)] md:grid md:gap-16 lg:gap-24">
          <%!-- Phones get no index: closed, the page is under three screens and its headings do the job. --%>
          <nav
            id="faq-nav"
            phx-hook=".SectionIndex"
            aria-labelledby="faq-nav-heading"
            class="top-[calc(var(--shy-header-offset,0px)+2rem)] transition-[top] sticky hidden self-start duration-200 ease-out motion-reduce:transition-none md:block"
          >
            <h2 id="faq-nav-heading" class="text-base-content/75 mb-3 text-sm">{~t"On this page"}</h2>
            <ul class="category-index m-0 list-none p-0">
              <li :for={{id, title, _questions} <- @sections}>
                <a href={"##{id}"} class="category-index__link text-base-content block py-1 no-underline">
                  <span class="category-index__name font-serif text-lg">{title}</span>
                </a>
              </li>
            </ul>
          </nav>

          <div class="space-y-16 md:space-y-20">
            <section
              :for={{id, title, questions} <- @sections}
              aria-labelledby={"#{id}-faq-heading"}
              class="scroll-mt-8"
              id={id}
            >
              <h2 id={"#{id}-faq-heading"} class="section-title mb-6">{title}</h2>
              <div class="max-w-3xl">
                <.faq_item :for={{question, answer} <- questions} question={question} answer={answer} />
              </div>
            </section>

            <section
              aria-labelledby="ask-heading"
              class="bg-cream text-cream-content flex max-w-3xl flex-col items-start gap-6 px-6 py-10 sm:px-10"
            >
              <h2 id="ask-heading" class="section-title text-balance">{~t"Didn't find your answer?"}</h2>
              <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
                <.button phx-click={ContactDrawer.open()} variant="primary">{~t"Send me a message"}</.button>
                <a href={"tel:#{Business.phone()}"} class="link-underline-static-body whitespace-nowrap">
                  {Business.phone_display()}
                </a>
              </div>
            </section>
          </div>
        </div>
      </.container>

      <.live_component module={ContactDrawer} id="contact-drawer" />
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SectionIndex">
      // Marks the section being read as the current one in the index. It's worked out from the
      // scroll position each time, so jumps (to the top, or to a link) can't leave a stale mark.
      export default {
        mounted() {
          const links = [...this.el.querySelectorAll("a[href^='#']")];
          const sections = links.map((link) =>
            document.getElementById(link.hash.slice(1)),
          );

          this.update = () => {
            const line = window.innerHeight * 0.25;
            // The last section is too short to reach the line, so the bottom of the page marks it.
            const atBottom =
              window.innerHeight + window.scrollY >=
              document.documentElement.scrollHeight - 2;
            const passed = sections.filter(
              (s) => s.getBoundingClientRect().top <= line,
            ).length;
            const current = atBottom ? links.length - 1 : Math.max(passed - 1, 0);

            links.forEach((link, i) => {
              if (i === current) link.setAttribute("aria-current", "location");
              else link.removeAttribute("aria-current");
            });
          };

          this.update();
          document.addEventListener("scroll", this.update, { passive: true });
        },

        destroyed() {
          document.removeEventListener("scroll", this.update);
        },
      };
    </script>
    """
  end

  @doc "Answered here and on a subscribable product's page."
  def subscription_questions do
    days = Subscription.lead_days()

    [
      {~t"Can I pick it up instead?", pickup_answer()},
      {~t"When do I pay?",
       ~t"For the first bouquet, at checkout. After that, your card is charged #{days = days} days before each one."},
      {~t"Can I take a break or stop?",
       ~t"Yes, from your account, where you can also change the size, how often or the day. Changes close #{close = Subscription.change_deadline_days()} days before a bouquet."},
      {~t"What if my card doesn't go through?",
       ~t"Your bouquet still comes, and I'll email you a payment link. Nothing more is sent or charged until it's paid or you add a new card."}
    ]
  end

  # An answer is a list of blocks: a paragraph (a string), {:list, lines} or
  # {:link, text, path}. Links show on the page but stay out of the JSON-LD.
  defp sections do
    [
      {"delivery", ~t"Delivery and pickup",
       [
         {~t"Where do you deliver?", delivery_area_answer()},
         {~t"Do you deliver to hospitals?",
          [
            ~t"Yes, to the ward, if it allows flowers. Please check with the ward first, and put the patient's name and ward in the delivery instructions."
          ]},
         {~t"What if nobody's home?",
          [
            ~t"I leave the flowers at the door and email you a photo of where. For gifts, I also email you when they're delivered. Add any door code to the delivery instructions.",
            {:link, ~t"What happens if I can't get in", terms_path("delivery")}
          ]},
         {~t"Where and when can I pick up my order?",
          [
            ~t"At Minimossen, #{address = Business.street_address()}, #{town = Business.postal_town()}. I'll message you when your order is ready. Collect it during opening hours, or get in touch for another time.",
            {:list, Business.opening_hours_lines()}
          ]}
       ]},
      {"ordering", ~t"Ordering",
       [
         {~t"Can I order something that isn't in the store?",
          [
            ~t"Yes. Tell me what you have in mind.",
            {:link, ~t"Get in touch", ~q"/#{language}/contact"}
          ]},
         {~t"Can I add a card with a message?", card_answer()},
         {~t"Can I cancel an order I made online?",
          [
            ~t"Yes, from your account until #{days = Subscription.change_deadline_days()} days before delivery or pickup, for a full refund. After that, get in touch. I'm usually flexible.",
            {:link, ~t"See the cancellation terms", terms_path("cancellation")}
          ]}
       ]},
      {"care", ~t"Flowers and care",
       [
         {~t"How long will my flowers last?",
          [
            ~t"5–7 days with care. Change the water every 2–3 days, trim the stems, and keep them out of direct sun and drafts."
          ]},
         {~t"Are your flowers local and seasonal?",
          [
            ~t"Where I can. If a flower is out of season or unavailable, I use something similar of the same value.",
            {:link, ~t"See the substitution terms", terms_path("substitution")}
          ]},
         {~t"What if my flowers arrive damaged or wilt early?",
          [
            ~t"Send me a photo within 4 days and I'll replace them or refund you, as long as they've had fresh water.",
            {:link, ~t"See the quality terms", terms_path("quality")}
          ]}
       ]},
      {"payment", ~t"Payment",
       [
         {~t"How can I pay?", [~t"MobilePay, card, Apple Pay or Google Pay. Prices include VAT."]},
         {~t"Can businesses pay by invoice?",
          [
            ~t"Yes, and so can larger orders such as weddings.",
            {:link, ~t"Get in touch", ~q"/#{language}/contact"}
          ]}
       ]},
      {"subscriptions", ~t"Subscriptions", Enum.map(subscription_questions(), fn {q, a} -> {q, [a]} end)},
      {"weddings", ~t"Weddings",
       [
         {~t"How far ahead should I book wedding flowers?",
          [~t"The sooner the better, as my calendar fills up quickly."]},
         {~t"Do you do weddings outside Vaasa?", [~t"Yes, gladly. Travel is quoted separately."]},
         {~t"How does payment for a wedding work?",
          [
            ~t"Half is invoiced as a booking fee about 4 weeks before the wedding, the rest afterwards.",
            {:link, ~t"Read about wedding flowers", ~q"/#{language}/weddings"}
          ]}
       ]},
      {"courses", ~t"Courses",
       [
         {~t"How do I cancel a course booking?",
          [
            ~t"Reply to your confirmation email. Each course's page says how long you can cancel for a full refund, and what's kept after that."
          ]},
         {~t"What's included in a course, and what should I bring?",
          [
            ~t"It's on each course's page.",
            {:link, ~t"See the courses", ~q"/#{language}/courses"}
          ]},
         {~t"Can I book a private course for my group?",
          [
            ~t"Yes, at Minimossen or at your own premises.",
            {:link, ~t"Courses for private groups", ~q"/#{language}/courses" <> "#groups"}
          ]}
       ]}
    ]
  end

  defp terms_path(section), do: ~q"/#{language}/terms" <> "##{section}"

  # Sizes the catalogue has cards in, each with its message limit and lowest price.
  defp card_answer do
    locale = Format.locale()
    cards = Edenflowers.Catalog.list_card_drawer_variants!()

    sizes =
      for size <- ProductVariantSize.values(),
          variants = Enum.filter(cards, &(&1.size == size)),
          variants != [] do
        price = variants |> Enum.min_by(& &1.price, Decimal) |> Map.fetch!(:price)

        ~t"#{name = EdenflowersWeb.CardDrawer.size_label(size)}: up to #{chars = ProductVariantSize.max_message_length(size)} characters, from #{price = Format.currency(price, locale)}"
      end

    intro = ~t"Yes, on gifts. Choose a card at checkout and write your message."

    if sizes == [], do: [intro], else: [intro, {:list, sizes}]
  end

  defp delivery_area_answer do
    locale = Format.locale()

    area =
      case Edenflowers.Fulfillment.distance_priced_delivery() do
        %{max_dist_km: max, base_price: base, price_per_km: per_km} when is_integer(max) ->
          ~t"Within #{km = max} km of the shop, for #{base = Format.currency(base, locale)} plus #{per_km = Format.currency(per_km, locale)} per km. Checkout shows the exact price."

        _ ->
          ~t"Enter the address at checkout to see whether I deliver there and what it costs."
      end

    free =
      if km = Edenflowers.Fulfillment.free_dist_km(),
        do: ~t"Some products, like subscriptions, are delivered free within #{km = km} km."

    Enum.reject([area, free, same_day_answer()], &is_nil/1)
  end

  defp same_day_answer do
    calendar = Edenflowers.Fulfillment.get_shop_calendar!()

    if calendar.same_day do
      time = Format.time(calendar.order_deadline, Format.locale())

      ~t"Order by #{time = time} for delivery the same day."
    else
      ~t"The earliest delivery is the next day the shop is open."
    end
  end

  # Free-delivery products, subscriptions among them, get the free distance;
  # past it, the option's usual fee applies, counted from the shop.
  defp pickup_answer do
    case Edenflowers.Fulfillment.distance_priced_delivery() do
      %{free_dist_km: km, base_price: base, price_per_km: per_km} when km > 0 ->
        locale = Format.locale()

        ~t"Of course, choose pickup at checkout. Delivered, it's free within #{km = km} km, then #{base = Format.currency(base, locale)} plus #{per_km = Format.currency(per_km, locale)} per km further out."

      _ ->
        ~t"Of course, choose pickup at checkout."
    end
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
      {:link, _text, _path} -> []
      {:list, lines} -> Enum.map(lines, &(&1 <> "."))
      paragraph -> [paragraph]
    end)
    |> Enum.join(" ")
  end

  attr :question, :string, required: true
  attr :answer, :list, required: true

  defp faq_item(assigns) do
    ~H"""
    <details class="collapse-arrow border-base-content/12 collapse rounded-none border-b has-[summary:focus-visible]:outline-primary has-[summary:focus-visible]:outline-2 has-[summary:focus-visible]:outline-offset-2 first-of-type:border-t">
      <summary class="collapse-title font-serif text-balance pr-10 pl-0 text-xl leading-snug">
        {@question}
      </summary>
      <div class="collapse-content text-[1.0625rem] max-w-[60ch] space-y-3 px-0 leading-relaxed">
        <.answer_block :for={block <- @answer} block={block} />
      </div>
    </details>
    """
  end

  defp answer_block(%{block: {:list, lines}} = assigns) do
    assigns = assign(assigns, :lines, lines)

    ~H"""
    <ul>
      <li :for={line <- @lines}>{line}</li>
    </ul>
    """
  end

  defp answer_block(%{block: {:link, text, path}} = assigns) do
    assigns = assign(assigns, text: text, path: path)

    ~H"""
    <p><a class="link-underline-static-body" href={@path}>{@text}</a></p>
    """
  end

  defp answer_block(assigns) do
    ~H"""
    <p>{@block}</p>
    """
  end
end
