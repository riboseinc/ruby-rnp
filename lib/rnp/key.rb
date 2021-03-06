# frozen_string_literal: true

# (c) 2018-2020 Ribose Inc.

require 'ffi'

require 'rnp/error'
require 'rnp/ffi/librnp'
require 'rnp/utils'
require 'rnp/userid'

class Rnp
  # Class that represents a PGP key (potentially encompassing both the public
  # and private portions).
  class Key
    # @api private
    attr_reader :ptr

    # @api private
    def initialize(ptr, free = true)
      raise Rnp::Error, 'NULL pointer' if ptr.null?
      if free
        @ptr = FFI::AutoPointer.new(ptr, self.class.method(:destroy))
      else
        @ptr = ptr
      end
    end

    # @api private
    def self.destroy(ptr)
      LibRnp.rnp_key_handle_destroy(ptr)
    end

    def inspect
      Rnp.inspect_ptr(self)
    end

    def to_s
      "#<#{self.class}:#{keyid}>"
    end

    # Get the fingerprint of the key
    #
    # @return [String]
    def fingerprint
      string_property(:rnp_key_get_fprint)
    end

    # Get the keyid of the key
    #
    # @return [String]
    def keyid
      string_property(:rnp_key_get_keyid)
    end

    # Get the grip of the key
    #
    # @return [String]
    def grip
      string_property(:rnp_key_get_grip)
    end

    # Get the primary grip of the key (for subkeys)
    #
    # @return [String]
    def primary_grip
      string_property(:rnp_key_get_primary_grip)
    end

    # Get the primary userid of the key
    #
    # @return [String]
    def primary_userid
      string_property(:rnp_key_get_primary_uid)
    end

    # Enumerate each userid for this key.
    #
    # @return [self, Enumerator]
    def each_userid(&block)
      block or return enum_for(:userid_iterator)
      userid_iterator(&block)
      self
    end

    # Get a list of all userids for this key.
    #
    # @return [Array<String>]
    def userids
      each_userid.to_a
    end

    # Enumerate each {UserID} for this key.
    #
    # @return [self, Enumerator]
    def each_uid(&block)
      block or return enum_for(:uid_iterator)
      uid_iterator(&block)
      self
    end

    # Get a list of {UserID}s for this key.
    #
    # @return [Array<UserID>]
    def uids
      each_uid.to_a
    end

    # Enumerate each {Signature} for this key.
    #
    # @return [self, Enumerator]
    def each_signature(&block)
      block or return enum_for(:signature_iterator)
      signature_iterator(&block)
      self
    end

    # Get a list of {Signature}s for this key.
    #
    # @return [Array<Signature>]
    def signatures
      each_signature.to_a
    end

    # Add a userid to a key.
    #
    # @param userid [String] the userid to add
    # @param hash (see Sign#hash=)
    # @param expiration_time (see Sign#expiration_time=)
    # @param key_flags [Integer]
    # @param primary [Boolean] if true then this userid will be marked as the
    #   primary userid
    # @return [void]
    def add_userid(userid, hash: nil, expiration_time: 0, key_flags: 0,
                   primary: false)
      Rnp.call_ffi(:rnp_key_add_uid, @ptr, userid, hash, expiration_time,
                   key_flags, primary)
    end

    # Returns true if the key is currently locked.
    #
    # @return [Boolean]
    def locked?
      bool_property(:rnp_key_is_locked)
    end

    # Lock the key.
    #
    # @return [self]
    def lock
      Rnp.call_ffi(:rnp_key_lock, @ptr)
      self
    end

    # Unlock the key.
    #
    # @param password [String, nil] the password to unlock the key. If nil, the
    #   current password provider will be used (see {Rnp#password_provider=}).
    # @return [self]
    def unlock(password = nil)
      Rnp.call_ffi(:rnp_key_unlock, @ptr, password)
      self
    end

    # Returns true if the key is currently protected.
    #
    # @return [Boolean]
    def protected?
      bool_property(:rnp_key_is_protected)
    end

    # Protect or re-protect the key.
    #
    # @param password [String] the password with which to encrypt the key.
    # @param cipher [String] the cipher algorithm to encrypt with
    # @param cipher_mode [String] the cipher mode
    # @param s2k_hash (see Encrypt#add_password)
    # @param s2k_iterations (see Encrypt#add_password)
    # @return [self]
    def protect(password, cipher: nil, cipher_mode: nil, s2k_hash: nil,
                s2k_iterations: 0)
      Rnp.call_ffi(:rnp_key_protect, @ptr, password, cipher, cipher_mode,
                   s2k_hash, s2k_iterations)
      self
    end

    # Unprotect the key.
    #
    # @param password [String, nil] the password to unlock the key. If nil,
    #   the current password provider will be used (see {Rnp#password_provider=}).
    # @return [self]
    def unprotect(password = nil)
      Rnp.call_ffi(:rnp_key_unprotect, @ptr, password)
      self
    end

    # Returns true if the key is a primary key.
    #
    # @return [Boolean]
    def primary?
      bool_property(:rnp_key_is_primary)
    end

    # Returns true if the key is a subkey.
    #
    # @return [Boolean]
    def sub?
      bool_property(:rnp_key_is_sub)
    end

    # Returns true if the public key packet is available.
    #
    # @return [Boolean]
    def public_key_present?
      bool_property(:rnp_key_have_public)
    end

    # Returns true if the secret key packet is available.
    #
    # @return [Boolean]
    def secret_key_present?
      bool_property(:rnp_key_have_secret)
    end

    # Export a public key.
    #
    # By default, when exporting a primary key, only the primary key
    # will be exported. When exporting a subkey, the primary key and
    # subkey will both be exported.
    #
    # @param output [Output] the output to write the exported key.
    #   If nil, the result will be returned directly as a String.
    # @param armored (see Sign#armored=)
    # @param with_subkeys [Boolean] when exporting a primary key,
    #   this controls whether all subkeys should also be exported.
    #   When true, the primary key and all subkeys will be exported.
    #   When false, only the primary key will be exported.
    #   This parameter is not valid when the key is a subkey.
    # @return [nil, String]
    def export_public(armored: true, with_subkeys: false, output: nil)
      Output.default(output) do |output_|
        export(public_key: true, with_subkeys: with_subkeys, armored: armored, output: output_)
      end
    end

    # Export a secret key.
    #
    # By default, when exporting a primary key, only the primary key
    # will be exported. When exporting a subkey, the primary key and
    # subkey will both be exported.
    #
    # @param output [Output] the output to write the exported key.
    #   If nil, the result will be returned directly as a String.
    # @param armored (see Sign#armored=)
    # @param with_subkeys [Boolean] when exporting a primary key,
    #   this controls whether all subkeys should also be exported.
    #   When true, the primary key and all subkeys will be exported.
    #   When false, only the primary key will be exported.
    #   This parameter is not valid when the key is a subkey.
    # @return [nil, String]
    def export_secret(armored: true, with_subkeys: false, output: nil)
      Output.default(output) do |output_|
        export(secret_key: true, with_subkeys: with_subkeys, armored: armored, output: output_)
      end
    end

    # Returns the raw public key data as PGP packets.
    #
    # @return [String]
    def public_key_data
      buf_property(:rnp_get_public_key_data)
    end

    # Returns the raw secret key data.
    #
    # The format may be either PGP packets or an s-expr/G10.
    #
    # @return [String]
    def secret_key_data
      buf_property(:rnp_get_secret_key_data)
    end

    # Return a JSON representation of this key (as a Hash).
    #
    # @param public_mpis [Boolean] if true then public MPIs will be included
    # @param secret_mpis [Boolean] if true then secret MPIs will be included
    # @param signatures [Boolean] if true then signatures will be included
    # @param signature_mpis [Boolean] if true then signature MPIs will be
    #   included
    # @return [Hash]
    def json(public_mpis: false, secret_mpis: false, signatures: true,
             signature_mpis: false)
      flags = 0
      flags |= LibRnp::RNP_JSON_PUBLIC_MPIS if public_mpis
      flags |= LibRnp::RNP_JSON_SECRET_MPIS if secret_mpis
      flags |= LibRnp::RNP_JSON_SIGNATURES if signatures
      flags |= LibRnp::RNP_JSON_SIGNATURE_MPIS if signature_mpis
      pptr = FFI::MemoryPointer.new(:pointer)
      Rnp.call_ffi(:rnp_key_to_json, @ptr, flags, pptr)
      begin
        presult = pptr.read_pointer
        JSON.parse(presult.read_string) unless presult.null?
      ensure
        LibRnp.rnp_buffer_destroy(presult)
      end
    end

    # Unload this key.
    #
    # @note When both the public and secret portions of this key have been
    # unloaded, you should no longer interact with this object.
    #
    # @param unload_public [Boolean] if true then the public key will be
    #   unloaded
    # @param unload_secret [Boolean] if true then the secret  key will be
    #   unloaded
    # @return [void]
    def unload(unload_public: true, unload_secret: true)
      flags = 0
      flags |= LibRnp::RNP_KEY_REMOVE_PUBLIC if unload_public
      flags |= LibRnp::RNP_KEY_REMOVE_SECRET if unload_secret
      Rnp.call_ffi(:rnp_key_remove, @ptr, flags)
    end

    # Enumerate each subkey for this key.
    #
    # @return [self, Enumerator]
    def each_subkey(&block)
      block or return enum_for(:subkey_iterator)
      subkey_iterator(&block)
      self
    end

    # Get a list of all subkeys for this key.
    #
    # @return [Array<Key>]
    def subkeys
      each_subkey.to_a
    end

    # Get the type of this key (RSA, etc).
    #
    # @return [String]
    def type
      string_property(:rnp_key_get_alg)
    end

    # Get the bit length for this key.
    #
    # @return [Integer]
    def bits
      pbits = FFI::MemoryPointer.new(:uint32)
      Rnp.call_ffi(:rnp_key_get_bits, @ptr, pbits)
      pbits.read(:uint32)
    end

    # Get the bit length for the q parameter of this DSA key.
    #
    # @return [Integer]
    def qbits
      pbits = FFI::MemoryPointer.new(:uint32)
      Rnp.call_ffi(:rnp_key_get_dsa_qbits, @ptr, pbits)
      pbits.read(:uint32)
    end

    # Get the curve of this EC key.
    #
    # @return [String]
    def curve
      string_property(:rnp_key_get_curve)
    end

    # Query whether this key can be used to perform a certain operation.
    #
    # @param op [String,Symbol] the operation to query (sign, etc)
    # @return [Boolean]
    def can?(op)
      pvalue = FFI::MemoryPointer.new(:bool)
      Rnp.call_ffi(:rnp_key_allows_usage, @ptr, op.to_s, pvalue)
      pvalue.read(:bool)
    end

    # Check if this has been revoked.
    #
    # @return [Boolean]
    def revoked?
      bool_property(:rnp_key_is_revoked)
    end

    # Check if this revoked key's material was compromised.
    #
    # @return [Boolean]
    def compromised?
      bool_property(:rnp_key_is_compromised)
    end

    # Check if this revoked key was retired.
    #
    # @return [Boolean]
    def retired?
      bool_property(:rnp_key_is_retired)
    end

    # Check if this revoked key was superseded by another key.
    #
    # @return [Boolean]
    def superseded?
      bool_property(:rnp_key_is_superseded)
    end

    # Retrieve the reason for revoking this key, if any.
    #
    # @return [String]
    def revocation_reason
      string_property(:rnp_key_get_revocation_reason)
    end

    # Retrieve the creation time of the key
    #
    # @return [Time]
    def creation_time
      ptime = FFI::MemoryPointer.new(:uint32)
      Rnp.call_ffi(:rnp_key_get_creation, @ptr, ptime)
      Time.at(ptime.read(:uint32))
    end

    # Retrieve the expiration time of the key
    #
    # @return [Time]
    def expiration_time
      ptime = FFI::MemoryPointer.new(:uint32)
      Rnp.call_ffi(:rnp_key_get_expiration, @ptr, ptime)
      Time.at(ptime.read(:uint32))
    end

    private

    def string_property(func)
      pptr = FFI::MemoryPointer.new(:pointer)
      Rnp.call_ffi(func, @ptr, pptr)
      begin
        pvalue = pptr.read_pointer
        pvalue.read_string unless pvalue.null?
      ensure
        LibRnp.rnp_buffer_destroy(pvalue)
      end
    end

    def bool_property(func)
      presult = FFI::MemoryPointer.new(:bool)
      Rnp.call_ffi(func, @ptr, presult)
      presult.read(:bool)
    end

    def buf_property(func)
      pptr = FFI::MemoryPointer.new(:pointer)
      pbuflen = FFI::MemoryPointer.new(:size_t)
      Rnp.call_ffi(func, @ptr, pptr, pbuflen)
      begin
        pbuf = pptr.read_pointer
        buflen = pbuflen.read(:size_t)
        pbuf.read_bytes(buflen) unless pbuf.null?
      ensure
        LibRnp.rnp_buffer_destroy(pbuf)
      end
    end

    def userid_iterator
      pcount = FFI::MemoryPointer.new(:size_t)
      Rnp.call_ffi(:rnp_key_get_uid_count, @ptr, pcount)
      count = pcount.read(:size_t)
      pptr = FFI::MemoryPointer.new(:pointer)
      (0...count).each do |i|
        Rnp.call_ffi(:rnp_key_get_uid_at, @ptr, i, pptr)
        begin
          puserid = pptr.read_pointer
          yield puserid.read_string unless puserid.null?
        ensure
          LibRnp.rnp_buffer_destroy(puserid)
        end
      end
    end

    def uid_iterator
      pcount = FFI::MemoryPointer.new(:size_t)
      Rnp.call_ffi(:rnp_key_get_uid_count, @ptr, pcount)
      count = pcount.read(:size_t)
      pptr = FFI::MemoryPointer.new(:pointer)
      (0...count).each do |i|
        Rnp.call_ffi(:rnp_key_get_uid_handle_at, @ptr, i, pptr)
        begin
          phandle = pptr.read_pointer
          puserid = nil
          next if phandle.nil?
          Rnp.call_ffi(:rnp_key_get_uid_at, @ptr, i, pptr)
          puserid = pptr.read_pointer
          yield UserID.new(phandle, puserid.read_string) unless puserid.null?
          phandle = nil
        ensure
          LibRnp.rnp_uid_handle_destroy(phandle)
          LibRnp.rnp_buffer_destroy(puserid)
        end
      end
    end

    def signature_iterator
      pcount = FFI::MemoryPointer.new(:size_t)
      Rnp.call_ffi(:rnp_key_get_signature_count, @ptr, pcount)
      count = pcount.read(:size_t)
      pptr = FFI::MemoryPointer.new(:pointer)
      (0...count).each do |i|
        Rnp.call_ffi(:rnp_key_get_signature_at, @ptr, i, pptr)
        psig = pptr.read_pointer
        yield Signature.new(psig) unless psig.null?
      end
    end

    def export(public_key: false, secret_key: false, with_subkeys: false, armored: true, output: nil)
      flags = 0
      flags |= LibRnp::RNP_KEY_EXPORT_ARMORED if armored
      flags |= LibRnp::RNP_KEY_EXPORT_PUBLIC if public_key
      flags |= LibRnp::RNP_KEY_EXPORT_SECRET if secret_key
      flags |= LibRnp::RNP_KEY_EXPORT_SUBKEYS if with_subkeys
      Rnp.call_ffi(:rnp_key_export, @ptr, output.ptr, flags)
    end

    def subkey_iterator
      pcount = FFI::MemoryPointer.new(:size_t)
      Rnp.call_ffi(:rnp_key_get_subkey_count, @ptr, pcount)
      count = pcount.read(:size_t)
      pptr = FFI::MemoryPointer.new(:pointer)
      (0...count).each do |i|
        Rnp.call_ffi(:rnp_key_get_subkey_at, @ptr, i, pptr)
        begin
          psubkey = pptr.read_pointer
          yield Rnp::Key.new(psubkey) unless psubkey.null?
        end
      end
    end
  end # class
end # class

