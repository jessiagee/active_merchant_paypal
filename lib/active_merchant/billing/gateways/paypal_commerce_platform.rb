require 'active_merchant/billing/gateways/paypal_commerce_platform/paypal_commerce_platform_common'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PaypalCommercePlatformGateway < Gateway
      include PaypalCommercePlatformCommon

      self.supported_countries = ['US']
      self.homepage_url        = 'https://www.paypal.com/cgi-bin/webscr?cmd=xpt/merchant/ExpressCheckoutIntro-outside'
      self.display_name        = 'PayPal Commerce Platform Checkout'


      def create_order(intent, options)
        #validate_intent(intent)
        requires!(options.merge!(intent.nil? ? { } : { intent: intent}), :intent, :purchase_units)

        post = { }
        add_intent(intent, post)
        add_purchase_units(options[:purchase_units], post)
        add_payment_instruction(options[:payment_instruction], post) unless options[:payment_instruction].blank?
        add_application_context(options[:application_context], post) unless options[:application_context].blank?

        commit(:post, "v2/checkout/orders", post, options[:headers])
      end


      def get_token(options)
        requires!(options[:authorization], :username, :password)
        prepare_request_for_get_access_token(options)
      end


      def authorize(order_id, options)
        requires!({ order_id: order_id }, :order_id)

        post = { }
        add_payment_source(options[:payment_source], post) unless options[:payment_source].nil?

        commit(:post, "v2/checkout/orders/#{ order_id }/authorize", post, options[:headers])
      end


      def handle_approve(operator_required_id, options)
        requires!(options.merge({ operator_required_id: operator_required_id }), :operator_required_id, :operator)
        options[:operator] == "authorize" ? authorize(operator_required_id, options) : capture(operator_required_id, options)
      end


      def capture(order_id, options)
        requires!({ order_id: order_id }, :order_id)

        post = { }
        add_payment_source(options[:payment_source], post) unless options[:payment_source].nil?

        commit(:post, "v2/checkout/orders/#{ order_id }/capture", post, options[:headers])
      end


      def refund(capture_id, options={ })
        requires!({ capture_id: capture_id }, :capture_id)

        post = { }
        add_amount(options[:amount], post) unless options[:amount].nil?
        add_invoice(options[:invoice_id], post) unless options[:invoice_id].nil?
        add_note(options[:note_to_payer], post) unless options[:note_to_payer].nil?

        commit(:post, "v2/payments/captures/#{ capture_id }/refund", post, options[:headers])
      end


      def void(authorization_id, options)
        requires!({ authorization_id: authorization_id }, :authorization_id)
        post = { }
        commit(:post, "v2/payments/authorizations/#{ authorization_id }/void", post, options[:headers])
      end


      def update_order(order_id, options)
        requires!(options.merge!(order_id.nil? ? { } : { order_id: order_id}), :order_id, :body)

        post = [ ]
        options[:body].each do |update|
          requires!(update, :op, :path, :value)

          update_hsh = { }
          update_hsh[:op]    = update[:op]
          update_hsh[:path]  = update[:path]

          type = get_update_type(update_hsh[:path])
          add_amount(update[:value], update_hsh, :value)           if type.eql?("amount")
          add_shipping_address(update[:value], update_hsh, :value) if type.eql?("address")
          add_payment_instruction(update[:value], update_hsh, :value) if type.eql?("payment_instruction")

          post.append(update_hsh)
        end

        commit(:patch, "v2/checkout/orders/#{ order_id }", post, options[:headers])
      end


      def do_capture(authorization_id, options)
        requires!(options.merge!({ authorization_id: authorization_id  }), :authorization_id)

        post = { }
        add_amount(options[:amount], post) unless options[:amount].nil?
        add_invoice(options[:invoice_id], post) unless options[:invoice_id].nil?
        add_final_capture(options[:final_capture], post) unless options[:final_capture].nil?
        add_payment_instruction(options[:payment_instruction], post) unless options[:payment_instruction].nil?

        commit(:post, "v2/payments/authorizations/#{ authorization_id }/capture", post, options[:headers])
      end


      def get_order_details(order_id, options)
        requires!(options.merge(order_id: order_id), :order_id)
        commit(:get, "/v2/checkout/orders/#{ order_id }", nil, options[:headers])
      end


      def get_authorization_details(authorization_id, options)
        requires!(options.merge(authorization_id: authorization_id), :authorization_id)
        commit(:get, "/v2/checkout/orders/#{ authorization_id }", nil, options[:headers])
      end


      def get_capture_details(capture_id, options)
        requires!(options.merge(capture_id: capture_id), :capture_id)
        commit(:get, "/v2/payments/captures/#{ capture_id }", nil, options[:headers])
      end


      def get_refund_details(refund_id, options)
        requires!(options.merge(refund_id: refund_id), :refund_id)
        commit(:get, "/v2/payments/refunds/#{ refund_id }", nil, options[:headers])
      end


      private


      def add_purchase_units(options, post)
        post[:purchase_units] = []

        options.map do |purchase_unit|
          requires!(purchase_unit, :amount)

          purchase_unit_hsh = {  }
          purchase_unit_hsh[:reference_id]      = purchase_unit[:reference_id] unless purchase_unit[:reference_id].nil?
          purchase_unit_hsh[:description]       = purchase_unit[:description] unless purchase_unit[:description].nil?
          purchase_unit_hsh[:shipping_method]   = purchase_unit[:shipping_method] unless purchase_unit[:shipping_method].nil?
          purchase_unit_hsh[:payment_group_id]  = purchase_unit[:payment_group_id] unless purchase_unit[:payment_group_id].nil?
          purchase_unit_hsh[:custom_id]         = purchase_unit[:custom_id] unless purchase_unit[:custom_id].nil?
          purchase_unit_hsh[:invoice_id]        = purchase_unit[:invoice_id] unless purchase_unit[:invoice_id].nil?
          purchase_unit_hsh[:soft_descriptor]   = purchase_unit[:soft_descriptor] unless purchase_unit[:soft_descriptor].nil?

          add_amount(purchase_unit[:amount], purchase_unit_hsh)
          add_payee(purchase_unit[:payee], purchase_unit_hsh) unless purchase_unit[:payee].nil?
          add_items(purchase_unit[:items], purchase_unit_hsh) unless purchase_unit[:items].nil?
          add_shipping(purchase_unit[:shipping], purchase_unit_hsh) unless purchase_unit[:shipping].nil?
          add_payment_instruction(purchase_unit[:payment_instruction], purchase_unit_hsh) unless purchase_unit[:payment_instruction].blank?

          post[:purchase_units] << purchase_unit_hsh
        end

        post
      end


      def add_application_context(options, post)
        post[:application_context]                = { }
        post[:application_context][:return_url]   = options[:return_url] unless options[:return_url].nil?
        post[:application_context][:cancel_url]   = options[:cancel_url] unless options[:cancel_url].nil?

        skip_empty(post, :application_context)
      end


      def add_payment_instruction(options, post, key=:payment_instruction)
        post[key]                     = { }
        post[key][:platform_fees]     = []
        post[key][:disbursement_mode] = options[:disbursement_mode] unless options[:disbursement_mode].nil?

        options[:platform_fees].map do |platform_fee|
          requires!(platform_fee, :amount, :payee)

          platform_fee_hsh = { }
          add_amount(platform_fee[:amount], platform_fee_hsh)
          add_payee(platform_fee[:payee], platform_fee_hsh)

          post[key][:platform_fees] << platform_fee_hsh
        end

        skip_empty(post, key)
      end


      def add_intent(intent, post)
        post[:intent]  = intent
        post
      end


      def add_payee(payee_obj, obj_hsh)
        obj_hsh[:payee] = { }
        obj_hsh[:payee][:merchant_id]         = payee_obj[:merchant_id] unless payee_obj[:merchant_id].nil?
        obj_hsh[:payee][:email_address]       = payee_obj[:email_address] unless payee_obj[:email_address].nil?

        skip_empty(obj_hsh, :payee)
      end


      def add_amount(amount, post, key=:amount)
        requires!(amount, :currency_code, :value)

        post[key]                 = { }
        post[key][:currency_code] = amount[:currency_code]
        post[key][:value]         = amount[:value]

        add_breakdown_for_amount(amount[:breakdown], post, key) unless amount[:breakdown].blank?

        post
      end


      def add_breakdown_for_amount(options, post, key)
        post[key][:breakdown] = { }
        options.each do |item, _|
            add_amount(options[item], post[key][:breakdown], item)
        end
        skip_empty(post[key], :breakdown)
      end


      def add_items(options, post)
        post[:items] = []

        options.each do |item|
          requires!(item, :name, :quantity, :unit_amount)

          items_hsh = { }

          items_hsh[:name]     = item[:name]
          items_hsh[:sku]      = item[:sku] unless item[:sku].nil?
          items_hsh[:quantity] = item[:quantity]
          items_hsh[:category] = item[:category] unless item[:category].nil?

          add_amount(item[:unit_amount], items_hsh, :unit_amount)
          add_amount(item[:tax], items_hsh, :tax) unless item[:tax].nil?

          post[:items] << items_hsh
        end

        post
      end


      def add_shipping(options, post)
        post[:shipping] = { }
        post[:shipping] = { }
        add_shipping_address(options[:address], post[:shipping]) unless options[:address].nil?

        skip_empty(post, :shipping)
      end


      def add_shipping_address(address, obj_hsh, key = :address)
        requires!(address, :admin_area_2, :postal_code, :country_code )

        obj_hsh[key] = { }
        obj_hsh[key][:address_line_1] = address[:address_line_1] unless address[:address_line_1].nil?
        obj_hsh[key][:address_line_2] = address[:address_line_2] unless address[:address_line_2].nil?
        obj_hsh[key][:admin_area_1]   = address[:admin_area_1] unless address[:admin_area_1].nil?
        obj_hsh[key][:admin_area_2]   = address[:admin_area_2]
        obj_hsh[key][:postal_code]    = address[:postal_code]
        obj_hsh[key][:country_code]   = address[:country_code]

        obj_hsh
      end


      def add_billing_address(address, obj_hsh)
        requires!(address, :country_code )

        obj_hsh[:billing_address] = { }
        obj_hsh[:billing_address][:address_line_1] = address[:address_line_1] unless address[:address_line_1].nil?
        obj_hsh[:billing_address][:admin_area_1]   = address[:admin_area_1] unless address[:admin_area_1].nil?
        obj_hsh[:billing_address][:admin_area_2]   = address[:admin_area_2] unless address[:admin_area_2].nil?
        obj_hsh[:billing_address][:postal_code]    = address[:postal_code] unless address[:postal_code].nil?
        obj_hsh[:billing_address][:country_code]   = address[:country_code] unless address[:country_code].nil?

        obj_hsh
      end


      def add_invoice(invoice_id, post)
        post[:invoice_id]  = invoice_id
        post
      end


      def add_final_capture(final_capture, post)
        post[:final_capture] = final_capture
        post
      end
      

      def add_note(note, post)
        post[:note_to_payer] = note
        post
      end


      def add_payment_source(source, post)
        post[:payment_source] = { }
        add_customer_card(source[:card], post[:payment_source]) unless source[:card].nil?

        skip_empty(post, :payment_source)
      end


      def add_customer_card(card_details, post)
        requires!(card_details, :number, :expiry)

        post[:card] = { }
        post[:card][:name]          = card_details[:name] unless card_details[:name].nil?
        post[:card][:number]        = card_details[:number]
        post[:card][:expiry]        = card_details[:expiry]
        post[:card][:security_code] = card_details[:security_code] unless card_details[:security_code].nil?

        add_billing_address(card_details[:billing_address], post) unless card_details[:billing_address].nil?
      end
    end
  end
end
