module TT::Plugins::TrueBend
  class TransactionObserver < Sketchup::ModelObserver

    def initialize(&block) # rubocop:disable Lint/MissingSuper
      @callback = block
    end

    def onTransactionAbort(model)
      callback(model, :abort)
    end

    def onTransactionCommit(model)
      callback(model, :commit)
    end

    def onTransactionEmpty(model)
      callback(model, :empty)
    end

    def onTransactionRedo(model)
      callback(model, :redo)
    end

    def onTransactionStart(model)
      callback(model, :start)
    end

    def onTransactionUndo(model)
      callback(model, :undo)
    end

    private

    def callback(model, transaction_type)
      @callback.call(model, transaction_type)
    end

  end # class
end # module
