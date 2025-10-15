defmodule EdenflowersWeb.CoursesLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    upcoming_courses =
      Edenflowers.Services.Course.list_upcoming_courses!(load: [:total_registrations])

    socket =
      socket
      |> assign(upcoming_courses: upcoming_courses)

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="container">
        <!-- Hero Section with generous spacing -->
        <section class="pt-24 pb-16 md:pt-32 md:pb-24">
          <div class="max-w-4xl">
            <h1 class="font-serif mb-8 text-5xl leading-tight md:text-7xl">
              {gettext("Courses")}
            </h1>
            <p class="max-w-2xl text-xl leading-relaxed text-gray-600 md:text-2xl">
              {gettext(
                "Learn the art of flower arranging with our hands-on workshops. Each course is designed to inspire creativity and develop your skills."
              )}
            </p>
          </div>
        </section>
        
    <!-- Courses Grid -->
        <section class="pb-24 md:pb-32">
          <%= if Enum.empty?(@upcoming_courses) do %>
            <div class="py-16 text-center">
              <h2 class="font-serif mb-6 text-3xl text-gray-600 md:text-4xl">
                {gettext("No upcoming courses")}
              </h2>
              <p class="mx-auto max-w-md text-lg text-gray-500">
                {gettext("Check back soon for new workshops and courses.")}
              </p>
            </div>
          <% else %>
            <div class="grid gap-16 md:gap-24">
              <div :for={course <- @upcoming_courses} class="group">
                <.course_card course={course} />
              </div>
            </div>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  def course_card(assigns) do
    ~H"""
    <article class="max-w-4xl">
      <div class="grid items-start gap-12 md:grid-cols-2 md:gap-16">
        <!-- Course Image -->
        <div class="order-1 md:order-1">
          <div class="aspect-[4/3] overflow-hidden bg-gray-100">
            <%= if @course.image_slug do %>
              <img src={"/images/#{@course.image_slug}"} alt={@course.name} class="h-full w-full object-cover" />
            <% else %>
              <div class="flex h-full w-full items-center justify-center text-gray-400">
                <.icon name="hero-camera" class="h-12 w-12" />
              </div>
            <% end %>
          </div>
        </div>
        
    <!-- Course Details -->
        <div class="order-2 space-y-6 md:order-2">
          <header class="space-y-4">
            <h2 class="font-serif text-3xl leading-tight md:text-4xl">
              {@course.name}
            </h2>

            <div class="space-y-2 text-lg">
              <div class="flex items-center gap-3">
                <.icon name="hero-calendar" class="h-5 w-5 text-gray-500" />
                <time class="text-gray-700">
                  {Calendar.strftime(@course.date, "%B %d, %Y")}
                </time>
              </div>

              <div class="flex items-center gap-3">
                <.icon name="hero-clock" class="h-5 w-5 text-gray-500" />
                <span class="text-gray-700">
                  {Calendar.strftime(@course.start_time, "%I:%M %p")} - {Calendar.strftime(@course.end_time, "%I:%M %p")}
                </span>
              </div>

              <div class="flex items-center gap-3">
                <.icon name="hero-map-pin" class="h-5 w-5 text-gray-500" />
                <span class="text-gray-700">{@course.location_name}</span>
              </div>
            </div>
          </header>

          <div class="prose prose-lg max-w-none">
            <p class="leading-relaxed text-gray-600">
              {@course.description}
            </p>
          </div>

          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <span class="font-serif text-2xl font-medium">
                €{:erlang.float_to_binary(@course.price |> Decimal.to_float(), decimals: 0)}
              </span>

              <div class="text-sm text-gray-500">
                <%= if @course.total_registrations > 0 do %>
                  {ngettext(
                    "%{count} spot remaining",
                    "%{count} spots remaining",
                    @course.total_places - @course.total_registrations,
                    count: @course.total_places - @course.total_registrations
                  )}
                <% else %>
                  {ngettext("%{count} spot available", "%{count} spots available", @course.total_places,
                    count: @course.total_places
                  )}
                <% end %>
              </div>
            </div>

            <%= if Date.compare(@course.register_before, Date.utc_today()) == :gt do %>
              <button class="btn btn-primary btn-lg w-full px-12 md:w-auto">
                {gettext("Register Now")}
              </button>

              <p class="text-sm text-gray-500">
                {gettext("Registration closes")} {Calendar.strftime(@course.register_before, "%B %d, %Y")}
              </p>
            <% else %>
              <div class="space-y-2">
                <button class="btn btn-disabled btn-lg w-full px-12 md:w-auto" disabled>
                  {gettext("Registration Closed")}
                </button>
                <p class="text-sm text-gray-500">
                  {gettext("Registration closed on")} {Calendar.strftime(@course.register_before, "%B %d, %Y")}
                </p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </article>
    """
  end
end
