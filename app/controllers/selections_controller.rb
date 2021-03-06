require "net/http"

class SelectionsController < ApplicationController

  def create
    @trip = Trip.find(params[:trip_id])
    #Define params for API
    #Clean what is not needed (heritage from Skyscanner API)
    if params[:pick_up_location].nil? || params[:pick_up_location] == ""
      @pick_up_location = @trip.round_trip_flight.flight1_destination_airport_iata
    else
      @pick_up_location = Airport.find_by_name(params[:pick_up_location]).iata
    end

    if params[:drop_off_location].nil? || params[:drop_off_location] == ""
      @drop_off_location = @trip.round_trip_flight.flight2_origin_airport_iata
    else
       @drop_off_location = Airport.find_by_name(params[:drop_off_location]).iata
    end

    if !params[:pick_up_date_time].nil?
      @pick_up_date_time = Time.zone.parse(params[:pick_up_date_time])
    else
      @pick_up_date_time = @trip.round_trip_flight.flight1_landing_at
    end
    if !params[:drop_off_date_time].nil?
      @drop_off_date_time = Time.zone.parse(params[:drop_off_date_time])
    else
      @drop_off_date_time = @trip.round_trip_flight.flight2_take_off_at
    end

    @selection = Selection.new()
    @selection.save
    @search = @trip.search
    @region = @trip.round_trip_flight.region
    @currency = 'EUR'

    # Launch requests
    @unfiltered_car_rentals = get_car_rentals_for_trip(@trip, @region)
    # Exclude companies with hidden costs for fuel
    @car_rentals = filter_companies(@unfiltered_car_rentals)
    # @car_rentals is an array of instances of car_rentals
    @categories = ["Mini", "Economy", "Compact", "Intermediate", "Fullsize", "Premium"]
    @best_car_rentals = []
    @categories.each do |category|
      best_category_cars = get_best_cars(@car_rentals, category)
      @best_car_rentals << best_category_cars
    end
    @best_car_rentals = @best_car_rentals.flatten
    @car_margin = 1.1
    @best_car_rentals = apply_car_margin(@best_car_rentals, @car_margin)
    @best_car_rentals.each do |car_rental|
      car_rental.selection = @selection
      car_rental.save
    end
    options = {
      :trip_id => @trip.id,
      :pick_up_location => @pick_up_location,
      :drop_off_location => @drop_off_location,
      :pick_up_date_time => @pick_up_date_time,
      :drop_off_date_time => @drop_off_date_time
    }
    # Uncomment if you want to test with a seed
    # @car_rentals = [CarRental.all[0], CarRental.all[1], CarRental.all[2], CarRental.all[3], CarRental.all[4]]
    redirect_to selection_path(@selection, options)
  end

  def show
    @trip = Trip.find(params[:trip_id])
    @search = @trip.search
    @nb_travelers = @search.nb_adults.to_i + @search.nb_children.to_i + @search.nb_infants.to_i
    @selection = Selection.find(params[:id])
    @car_rentals = CarRental.where(selection_id: @selection.id)
    @region = @trip.round_trip_flight.region
    @region_airports = @region.airports.map { |iata| Airport.find_by_iata(iata)}
    @region_airports = @region_airports.map { |airport| define_airport_title(airport)}

    @car_selection = get_best_cars_per_category(@car_rentals)
    @recommended_car = get_recommended_car(@car_selection)
    @main_car = @trip.car_rental || @recommended_car
    @main_car_title = define_title(@trip)


    @pick_up_location = params[:pick_up_location]
    @drop_off_location = params[:drop_off_location]
    @pick_up_date_time = params[:pick_up_date_time]
    @drop_off_date_time = params[:drop_off_date_time]
    @nb_days = calculate_nb_days(@pick_up_date_time, @drop_off_date_time)

    @times = ["6 AM", "7 AM", "8 AM", "9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM", "5 PM", "6 PM", "7 PM", "8 PM", "9 PM", "10 PM" ]

    @status = "none"

    @options = {
      :trip_id => @trip.id,
      :pick_up_location => @pick_up_location,
      :drop_off_location => @drop_off_location,
      :pick_up_date_time => @pick_up_date_time,
      :drop_off_date_time => @drop_off_date_time,
      :selection_id => @selection
    }

    @pick_up_airport = Airport.find_by_iata(@pick_up_location)
    @drop_off_airport = Airport.find_by_iata(@drop_off_location)
    @main_car_airports_titles = [define_airport_title(@pick_up_airport), define_airport_title(@drop_off_airport)]
    @trip.car_rental.nil? ? @recap_opacity = 1 : @recap_opacity = 0
    @categories = ["Mini", "Economy", "Compact", "Intermediate", "Fullsize", "Premium"]
    @popover_partials = create_partial_array


    respond_to do |format|
      format.html {}
      format.js {}
    end

  end

  private

  def get_car_rentals_for_trip(trip, region)
    if @pick_up_location == @drop_off_location
      #Launch Amadeus api
      options = {
        pick_up_place: @pick_up_location,
        drop_off_place: @drop_off_location,
        pick_up_date_time: @pick_up_date_time,
        drop_off_date_time: @drop_off_date_time,
        currency: @currency,
      }
      car_rentals = (Rental::SmartRentalAgent.new(options).obtain_rentals_amadeus)
    else
      #Launch Amadeus api with origin location
      options = {
        pick_up_place: @pick_up_location,
        drop_off_place: @pick_up_location,
        pick_up_date_time: @pick_up_date_time,
        drop_off_date_time: @drop_off_date_time,
        currency: @currency,
      }
      car_rentals = (Rental::SmartRentalAgent.new(options).obtain_rentals_amadeus)
      car_rentals = apply_one_way_markup(car_rentals, region)
      car_rentals
    end
  end

  def get_best_cars_per_category(rentals)
    best_cars = {}
    best_cars[:mini] = get_best_cars(rentals, "Mini")
    best_cars[:economy] = get_best_cars(rentals, "Economy")
    best_cars[:compact] = get_best_cars(rentals, "Compact")
    best_cars[:intermediate] = get_best_cars(rentals, "Intermediate")
    best_cars[:fullsize] = get_best_cars(rentals, "Fullsize")
    best_cars[:premium] = get_best_cars(rentals, "Premium")
    best_cars
  end

  def get_best_cars(rentals, category)
    unique_sorted_cars = get_unique_sorted_cars(rentals, category)
    best_cars = unique_sorted_cars.first(5)
  end


  def get_unique_sorted_cars(rentals, category)
    cars = rentals.select {|rental| rental.category == category}
    sorted_cars = cars.sort_by { |rental| rental.price }
  end

  def get_recommended_car(car_selection)
    cheapest_per_cat = []
    car_selection = car_selection.reject {|category, car_rentals| category == :mini}
    car_selection = car_selection.reject {|category, car_rentals| car_rentals == []}
    car_selection.each do |category, car_rentals|
      cheapest_per_cat << car_selection[category].first
    end
    sorted_cheapest_per_category = cheapest_per_cat.sort_by { |rental| rental.price }
    recommended_car = sorted_cheapest_per_category.first
  end

  def calculate_nb_days(pick_up_date_time, drop_off_date_time)
    string_drop_off = Time.parse(drop_off_date_time).strftime("%Y %B %e")
    string_pick_up = Time.parse(pick_up_date_time).strftime("%Y %B %e")
    drop_off = Time.parse(string_drop_off)
    pick_up = Time.parse(string_pick_up)
    nb_days = ((drop_off - pick_up).fdiv(24 * 60 * 60) + 1).to_i
  end

  def apply_car_margin(best_car_rentals, car_margin)
    best_car_rentals.each do |rental|
      rental.price = rental.price * car_margin
    end
    best_car_rentals
  end

  def define_title(trip)
    trip.car_rental.nil? ? "OUR RECOMMENDATION" : "YOUR SELECTION"
  end

  def create_partial_array
    popover_partials = {}
    @categories.each do |cat|
      popover_partials[cat.downcase] = render_to_string(:partial => "car_popover", :locals => { :pop_cat => cat.downcase})
    end
    popover_partials
  end

  def define_airport_title(airport)
    if airport.cityname == airport.name
      return "#{airport.cityname} airport"
    else
      return "#{airport.cityname} (#{airport.name}) airport"
    end
  end

  def filter_companies(car_rentals)
    if @region.name == "Andalucia" || @region.name == "Northern Spain"
      car_rentals = car_rentals.delete_if { |rental| rental.company == "GOLDCAR" || rental.company == "GOLDCAR REN"}
    end
    car_rentals = car_rentals.delete_if { |rental| rental.company == "FOX RAC" || rental.company == "AUTO EUROPE" || rental.company == "ECONOMY"}
  end

  def apply_one_way_markup(car_rentals, region)
    # pour chaque car_rental
    filtered_rentals = []
    car_rentals.each do |rental|
      if Constants::ONEWAYMARKUP[region.name].keys.include?(rental.company)
        rental.price = rental.price.to_f + Constants::ONEWAYMARKUP[region.name][rental.company].to_f
        rental.save
        filtered_rentals << rental
      end
    end
    return filtered_rentals
  end

end

