from pydantic import BaseModel


class StatusResponse(BaseModel):
    status: str
    service: str
    version: str
