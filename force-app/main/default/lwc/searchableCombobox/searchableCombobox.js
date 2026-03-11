import { LightningElement, api, track } from "lwc";

const MAX_VISIBLE = 200;

export default class SearchableCombobox extends LightningElement {
    @api label = "";
    @api placeholder = "Search...";
    @api disabled = false;
    @api serverSearch = false;

    @track _options = [];
    @track _value = "";
    @track _inputValue = "";
    @track isOpen = false;
    @track focusedIndex = -1;

    _documentClickHandler;

    @api
    get options() {
        return this._options;
    }
    set options(val) {
        this._options = val || [];
        // If we have a value set but input is empty (initial load), show the label
        if (this._value && !this._inputValue) {
            const match = this._options.find((o) => o.value === this._value);
            if (match) {
                this._inputValue = match.label;
            }
        }
    }

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val || "";
        if (this._value) {
            const match = this._options.find((o) => o.value === this._value);
            if (match) {
                this._inputValue = match.label;
            }
        } else {
            this._inputValue = "";
        }
    }

    get isOpenString() {
        return this.isOpen ? "true" : "false";
    }

    get containerClass() {
        return "slds-form-element";
    }

    get comboboxClass() {
        return (
            "slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click" +
            (this.isOpen ? " slds-is-open" : "")
        );
    }

    get inputValue() {
        return this._inputValue;
    }

    get currentPlaceholder() {
        return this.placeholder;
    }

    get inputAriaLabel() {
        return this.label && this.label.trim() !== ""
            ? this.label.trim()
            : this.placeholder || "Search";
    }

    get showClearButton() {
        return this._value && !this.disabled;
    }

    get filteredOptions() {
        let filtered;
        if (this.serverSearch || !this._inputValue || this._value) {
            filtered = this._options;
        } else {
            const term = this._inputValue.toLowerCase();
            filtered = this._options.filter(
                (o) => o.label && o.label.toLowerCase().includes(term)
            );
        }
        return filtered.slice(0, MAX_VISIBLE).map((o, i) => ({
            ...o,
            isSelected: o.value === this._value,
            itemClass:
                "slds-media slds-listbox__option slds-listbox__option_plain slds-media_small" +
                (i === this.focusedIndex ? " slds-has-focus" : "") +
                (o.value === this._value ? " slds-is-selected" : "")
        }));
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    connectedCallback() {
        this._documentClickHandler = (event) => {
            if (!this.template.host.contains(event.target)) {
                this.closeDropdown();
            }
        };
        // Use mousedown so it fires before focus, avoiding open-then-close race
        document.addEventListener("mousedown", this._documentClickHandler);
    }

    disconnectedCallback() {
        if (this._documentClickHandler) {
            document.removeEventListener("mousedown", this._documentClickHandler);
        }
    }

    handleFocus() {
        if (!this.disabled) {
            // If a value is selected, clear input to show all options for re-selection
            if (this._value) {
                this._inputValue = "";
            }
            this.openDropdown();
        }
    }

    handleInput(event) {
        this._inputValue = event.target.value;
        this.focusedIndex = -1;

        // If user is typing, clear the current value
        if (this._value) {
            this._value = "";
            this.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
        }

        if (!this.isOpen) {
            this.openDropdown();
        }

        if (this.serverSearch) {
            this.dispatchEvent(
                new CustomEvent("search", { detail: { searchTerm: this._inputValue } })
            );
        }
    }

    handleKeyDown(event) {
        if (!this.isOpen) {
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                this.openDropdown();
                event.preventDefault();
            }
            return;
        }

        const opts = this.filteredOptions;
        switch (event.key) {
            case "ArrowDown":
                event.preventDefault();
                this.focusedIndex = Math.min(
                    this.focusedIndex + 1,
                    opts.length - 1
                );
                this.scrollToFocused();
                break;
            case "ArrowUp":
                event.preventDefault();
                this.focusedIndex = Math.max(this.focusedIndex - 1, 0);
                this.scrollToFocused();
                break;
            case "Enter":
                event.preventDefault();
                if (this.focusedIndex >= 0 && this.focusedIndex < opts.length) {
                    this.selectOption(opts[this.focusedIndex].value);
                }
                break;
            case "Escape":
                event.preventDefault();
                this.closeDropdown();
                // Restore label if value was set
                if (this._value) {
                    const match = this._options.find(
                        (o) => o.value === this._value
                    );
                    if (match) {
                        this._inputValue = match.label;
                    }
                }
                break;
            default:
                break;
        }
    }

    handleOptionClick(event) {
        const val = event.currentTarget.dataset.value;
        this.selectOption(val);
    }

    handleOptionHover(event) {
        const val = event.currentTarget.dataset.value;
        const opts = this.filteredOptions;
        const idx = opts.findIndex((o) => o.value === val);
        if (idx >= 0) {
            this.focusedIndex = idx;
        }
    }

    handleClear(event) {
        event.stopPropagation();
        this._value = "";
        this._inputValue = "";
        this.focusedIndex = -1;
        this.dispatchEvent(new CustomEvent("change", { detail: { value: "" } }));
        // Focus back on input
        const input = this.template.querySelector('[data-element="input"]');
        if (input) {
            input.focus();
        }
    }

    selectOption(val) {
        const match = this._options.find((o) => o.value === val);
        if (match) {
            this._value = match.value;
            this._inputValue = match.label;
            this.closeDropdown();
            this.dispatchEvent(
                new CustomEvent("change", { detail: { value: match.value } })
            );
        }
    }

    openDropdown() {
        this.isOpen = true;
        this.focusedIndex = -1;
    }

    closeDropdown() {
        this.isOpen = false;
        this.focusedIndex = -1;
    }

    scrollToFocused() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const focused = this.template.querySelector(".slds-has-focus");
            if (focused) {
                focused.scrollIntoView({ block: "nearest" });
            }
        });
    }
}
