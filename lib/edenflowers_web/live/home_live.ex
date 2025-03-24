defmodule EdenflowersWeb.HomeLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="relative border-b">
      <img src="/images/image_5.jpg" class="h-[100vh] w-full object-cover" alt="" />

      <div class="container absolute inset-0 flex flex-col justify-center gap-8 text-center">
        <h1 class="hero-heading text-neutral-content font-serif tracking-wide">
          Fresh flowers for <i>everyday</i> moments.
        </h1>
        <button class="btn btn-primary mx-auto lg:btn-lg">Shop Now</button>
      </div>
    </div>

    <div class="my-36 flex flex-col items-center px-4">
      <h1 class="font-serif leading-14 max-w-4xl text-center text-4xl font-light">
        Crafted for those with discerning taste, our flowers blend quality and style and arrive perfectly arranged at your door.
      </h1>
      <a class="mt-12 font-bold uppercase tracking-wider underline underline-offset-4" href={~p"/#about"}>
        Learn more
      </a>
    </div>
    """
  end
end
