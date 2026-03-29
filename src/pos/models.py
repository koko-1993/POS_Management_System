from dataclasses import dataclass


@dataclass
class Product:
    sku: str
    name: str
    price: float
    stock: int


@dataclass
class CartItem:
    sku: str
    name: str
    unit_price: float
    quantity: int

    @property
    def line_total(self) -> float:
        return round(self.unit_price * self.quantity, 2)
