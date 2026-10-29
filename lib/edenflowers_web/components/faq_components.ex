defmodule EdenflowersWeb.FaqComponents do
  @moduledoc "Shared FAQ answers and accordion presentation."

  use EdenflowersWeb, :html

  alias Edenflowers.Orders.Subscription

  attr :id, :string, required: true
  attr :question, :string, required: true
  attr :variant, :string, values: ["default", "product"], default: "default"
  slot :inner_block, required: true

  def faq_item(assigns) do
    ~H"""
    <details
      id={@id}
      phx-mounted={JS.ignore_attributes(["open"])}
      class="collapse-arrow border-base-content/12 collapse group overflow-visible rounded-none border-b has-[summary:focus-visible]:outline-primary has-[summary:focus-visible]:outline-2 has-[summary:focus-visible]:outline-offset-2 first-of-type:border-t"
    >
      <summary class={["collapse-title text-balance pr-10 pl-0 leading-snug group-open:min-h-0 group-open:pb-2", @variant == "default" && "font-sans text-base font-semibold", @variant == "product" && "font-serif text-xl"]}>
        {@question}
      </summary>
      <div class={["collapse-content max-w-[60ch] space-y-3 px-0 font-normal leading-relaxed", @variant == "default" && "font-sans text-base-content text-base", @variant == "product" && "text-base-content/80 text-[1.0625rem]"]}>
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  def subscription_questions do
    days = Subscription.lead_days()

    [
      {~t"Can I collect my subscription bouquets?", ~t"Yes, choose pickup at checkout. Pickup is always free."},
      {~t"When do I pay?",
       ~t"For the first bouquet, at checkout. After that, your card is charged #{days = days} days before each delivery or pickup."},
      {~t"Can I pause or cancel my subscription?",
       ~t"Yes, from your account. You can also change the size, frequency or delivery day. Make changes at least #{close = Subscription.change_deadline_days()} days before delivery or pickup. Cancelling after that stops future bouquets, but the booked bouquet still comes."},
      {~t"What if my card doesn't go through?",
       ~t"Your bouquet still comes, and I'll get in touch with payment instructions."}
    ]
  end
end
