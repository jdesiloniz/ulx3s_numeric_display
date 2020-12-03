class Hc164 {
    private:
        unsigned previous_cp;
        void init_hc164();
    public:
        Hc164();
        unsigned output_signals;
        void update(unsigned cp, unsigned dsa, unsigned dsb, unsigned mr);
};